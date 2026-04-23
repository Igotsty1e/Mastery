import http from 'node:http';
import { Duplex } from 'node:stream';
import type { Express } from 'express';

type HeaderValue = string | string[] | undefined;

class MockSocket extends Duplex {
  public readonly chunks: Buffer[] = [];
  public remoteAddress = '127.0.0.1';

  constructor() {
    super();
  }

  address() {
    return { port: 0 };
  }

  setTimeout() {
    return this;
  }
  setNoDelay() {
    return this;
  }
  setKeepAlive() {
    return this;
  }

  _read() {
    // no-op: request body is pushed to req directly
  }

  _write(chunk: any, encoding: BufferEncoding, callback: (error?: Error | null) => void) {
    const buf = Buffer.isBuffer(chunk)
      ? chunk
      : typeof chunk === 'string'
        ? Buffer.from(chunk, encoding)
        : Buffer.from(String(chunk));
    this.chunks.push(buf);
    callback(null);
  }
}

function decodeChunkedBody(raw: Buffer): Buffer {
  // Very small, defensive chunked decoder (enough for tests).
  const text = raw.toString('utf8');
  let offset = 0;
  const out: Buffer[] = [];
  while (offset < text.length) {
    const lineEnd = text.indexOf('\r\n', offset);
    if (lineEnd === -1) break;
    const sizeHex = text.slice(offset, lineEnd).trim();
    const size = parseInt(sizeHex, 16);
    if (!Number.isFinite(size) || size <= 0) break;
    const chunkStart = lineEnd + 2;
    const chunkEnd = chunkStart + size;
    out.push(Buffer.from(text.slice(chunkStart, chunkEnd), 'utf8'));
    offset = chunkEnd + 2; // skip \r\n after chunk
  }
  return Buffer.concat(out);
}

function parseHttpBody(raw: Buffer, headersText: string): Buffer {
  const sep = raw.indexOf('\r\n\r\n');
  const body = sep === -1 ? Buffer.alloc(0) : raw.subarray(sep + 4);
  const isChunked = /transfer-encoding:\s*chunked/i.test(headersText);
  return isChunked ? decodeChunkedBody(body) : body;
}

export interface InjectResult {
  status: number;
  headers: Record<string, HeaderValue>;
  text: string;
  json: unknown;
}

export async function inject(
  app: Express,
  opts: {
    method: string;
    path: string;
    headers?: Record<string, string>;
    json?: unknown;
  }
): Promise<InjectResult> {
  const socket = new MockSocket();
  const req = new http.IncomingMessage(socket as any);
  req.method = opts.method.toUpperCase();
  req.url = opts.path;
  req.headers = Object.fromEntries(
    Object.entries(opts.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v])
  );
  if (opts.json !== undefined) {
    // Skip body-parser stream reads (sandbox-friendly). Express's json parser
    // short-circuits when `req._body` is already set.
    (req as any)._body = true;
    (req as any).body = opts.json;
    req.headers['content-type'] ??= 'application/json';
  }

  const res = new http.ServerResponse(req);
  res.assignSocket(socket as any);

  const done = new Promise<InjectResult>((resolve) => {
    res.once('finish', () => {
      const raw = Buffer.concat(socket.chunks);
      const asText = raw.toString('utf8');
      const headerEnd = asText.indexOf('\r\n\r\n');
      const headersText = headerEnd === -1 ? asText : asText.slice(0, headerEnd);
      const body = parseHttpBody(raw, headersText);
      const text = body.toString('utf8');

      let json: unknown = undefined;
      try {
        json = text ? JSON.parse(text) : undefined;
      } catch {
        json = undefined;
      }

      resolve({
        status: res.statusCode,
        headers: res.getHeaders() as Record<string, HeaderValue>,
        text,
        json,
      });
    });
  });

  // Ensure the request stream is ended (even when we bypass body parsing).
  setImmediate(() => req.push(null));

  app.handle(req, res);
  return await done;
}

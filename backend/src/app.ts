import express from 'express';
import healthRouter from './routes/health';
import { makeLessonsRouter } from './routes/lessons';
import type { AiProvider } from './ai/interface';

const DEFAULT_ALLOWED_ORIGINS = [
  'https://mastery-web-igotsty1e.onrender.com',
  'http://localhost:3000',
  'http://localhost:8080',
  'http://localhost:57450', // Flutter web dev server
];

const allowedOrigins: string[] = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map(s => s.trim())
  : DEFAULT_ALLOWED_ORIGINS;

export function createApp(ai: AiProvider): express.Express {
  const app = express();
  app.set('trust proxy', 1);
  app.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && allowedOrigins.includes(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
    }
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.sendStatus(204); return; }
    next();
  });
  app.use(express.json());

  app.use(healthRouter);
  app.use(makeLessonsRouter(ai));

  app.use((_req, res) => {
    res.status(404).json({ error: 'not_found' });
  });

  app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    console.error(err);
    res.status(500).json({ error: 'internal_error' });
  });

  return app;
}

import express from 'express';
import healthRouter from './routes/health';
import { makeLessonsRouter } from './routes/lessons';
import type { AiProvider } from './ai/interface';

export function createApp(ai: AiProvider): express.Express {
  const app = express();
  app.set('trust proxy', 1);
  app.use((_req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (_req.method === 'OPTIONS') { res.sendStatus(204); return; }
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

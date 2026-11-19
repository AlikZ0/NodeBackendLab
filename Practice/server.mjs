import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import {
  addTask, normalizeTitle, paginate, parseObject, readInteger, routeStatus,
} from './tasks.mjs';

const MAX_BODY_BYTES = 8192;

async function readBody(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size <= MAX_BODY_BYTES) chunks.push(chunk);
  }
  return size > MAX_BODY_BYTES ? null : Buffer.concat(chunks).toString('utf8');
}

function send(res, status, value, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', ...headers });
  res.end(JSON.stringify(value));
}

export function createTaskServer() {
  let tasks = [];
  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const status = routeStatus(req.method, url.pathname);

      if (status === 200) {
        const offset = readInteger(url.searchParams.get('offset'), 0);
        const limit = readInteger(url.searchParams.get('limit'), 20);
        const items = paginate(tasks, offset, limit);
        return items === null
          ? send(res, 400, { error: 'Некорректная пагинация' })
          : send(res, 200, { items, total: tasks.length });
      }

      if (status === 201) {
        const body = await readBody(req);
        if (body === null) return send(res, 413, { error: 'Слишком большой запрос' });
        const title = normalizeTitle(parseObject(body));
        if (title === null) return send(res, 400, { error: 'Некорректный title или JSON' });
        tasks = addTask(tasks, title);
        return send(res, 201, tasks.at(-1));
      }

      if (status === 405) {
        return send(res, 405, { error: 'Метод не поддерживается' }, { Allow: 'GET, POST' });
      }

      send(res, 404, { error: 'Маршрут не найден' });
    } catch (error) {
      if (res.destroyed) return;
      if (res.headersSent) return res.destroy();
      send(res, 500, { error: 'Внутренняя ошибка сервера' });
    }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  createTaskServer().listen(3000, '127.0.0.1', () => {
    console.log('API: http://127.0.0.1:3000/tasks');
  });
}

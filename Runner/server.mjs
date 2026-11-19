import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { networkInterfaces } from 'node:os';

const IMAGE = 'node:24-bookworm-slim';
const HOST = process.argv[2];
const PORT = 4377;
const addresses = Object.values(networkInterfaces()).flat().filter(Boolean);
const isPrivate = /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/;
if (!HOST || !isPrivate.test(HOST) ||
    !addresses.some(({ address, family }) => family === 'IPv4' && address === HOST)) {
  console.error('Передай локальный IPv4-адрес Ubuntu. Посмотри его командой hostname -I.');
  process.exit(1);
}

const token = randomBytes(24).toString('hex');
const tokenHeader = Buffer.from('Bearer ' + token);
const MAX_REQUEST = 64 * 1024;
const MAX_OUTPUT = 12 * 1024;
let busy = false;

function reply(res, status, value) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(value));
}

function runInDocker(source) {
  const name = 'node-backend-lab-' + randomBytes(12).toString('hex');
  const marker = 'LAB_FINISHED_' + randomBytes(16).toString('hex');
  const processArgs = [
    'run', '--rm', '--pull=never', '--name', name, '--network', 'none',
    '--read-only', '--tmpfs', '/tmp:rw,nosuid,nodev,size=32m,mode=1777',
    '--memory', '192m', '--memory-swap', '192m', '--cpus', '1',
    '--pids-limit', '64', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
    '--user', 'node', '--workdir', '/tmp', '--env', 'HOME=/tmp',
    '--env', 'NPM_CONFIG_CACHE=/tmp/npm-cache', '-i', IMAGE,
    'node', '--input-type=module', '-',
  ];

  return new Promise(resolve => {
    const child = spawn('docker', processArgs, { stdio: ['pipe', 'pipe', 'pipe'] });
    let output = Buffer.alloc(0);
    let failure;
    const stop = reason => {
      if (failure) return;
      failure = reason;
      child.kill('SIGKILL');
    };
    const timer = setTimeout(() => stop('Превышен лимит времени (12 секунд).'), 12_000);
    const collect = chunk => {
      const remaining = MAX_OUTPUT - output.length;
      output = Buffer.concat([output, chunk.subarray(0, remaining)]);
      if (chunk.length > remaining) stop('Превышен лимит вывода.');
    };
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
    child.stdin.on('error', () => {});
    child.on('error', error => {
      failure = 'Не удалось запустить Docker: ' + error.message;
    });
    child.on('close', code => {
      clearTimeout(timer);
      const printed = output.toString('utf8');
      const finished = printed.includes(marker);
      const reason = failure ?? (code === 0 && !finished ? 'Выполнение завершилось до конца тестов.' : undefined);
      const result = {
        ok: code === 0 && !failure && finished,
        output: [reason, printed.replace(marker, '').trim()].filter(Boolean).join('\n'),
      };
      if (!failure) {
        resolve(result);
        return;
      }
      const cleanup = spawn('docker', ['rm', '-f', name], { stdio: 'ignore' });
      const cleanupTimer = setTimeout(() => cleanup.kill('SIGKILL'), 2000);
      cleanup.on('error', () => {});
      cleanup.on('close', () => {
        clearTimeout(cleanupTimer);
        resolve(result);
      });
    });
    child.stdin.end(source + "\n;console.log(" + JSON.stringify(marker) + ");\n");
  });
}

const server = createServer({ requestTimeout: 5000, headersTimeout: 5000 }, async (req, res) => {
  if (req.method !== 'POST' || req.url !== '/run') return reply(res, 404, { error: 'Маршрут не найден.' });
  const received = Buffer.from(req.headers.authorization ?? '');
  if (received.length !== tokenHeader.length || !timingSafeEqual(received, tokenHeader)) {
    return reply(res, 401, { error: 'Код подключения не совпадает.' });
  }
  if (busy) return reply(res, 429, { error: 'Дождись завершения предыдущей проверки.' });
  if (Number(req.headers['content-length']) > MAX_REQUEST) {
    res.setHeader('Connection', 'close');
    return reply(res, 413, { error: 'Слишком большой запрос.' });
  }

  busy = true;
  try {
    const chunks = [];
    let size = 0;
    const deadline = setTimeout(() => req.destroy(), 5000);
    try {
      for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_REQUEST) {
          res.setHeader('Connection', 'close');
          return reply(res, 413, { error: 'Слишком большой запрос.' });
        }
        chunks.push(chunk);
      }
    } finally {
      clearTimeout(deadline);
    }
    const { source } = JSON.parse(Buffer.concat(chunks).toString('utf8')) ?? {};
    if (typeof source !== 'string' || !source.trim()) {
      return reply(res, 400, { error: 'Нужен код решения.' });
    }
    reply(res, 200, await runInDocker(source));
  } catch {
    if (!res.headersSent && !res.destroyed) reply(res, 400, { error: 'Некорректный запрос.' });
  } finally {
    busy = false;
  }
});

server.on('error', error => {
  console.error(error.message);
  process.exitCode = 1;
});
server.listen(PORT, HOST, () => {
  console.log('Введи в приложении адрес ' + HOST + ' и код подключения:\n' + token);
  console.log('Остановка — Ctrl+C.');
});

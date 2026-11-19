import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { createTaskServer } from './server.mjs';
import {
  addTask, normalizeTitle, paginate, parseObject, readInteger, routeStatus,
} from './tasks.mjs';

test('validation', () => {
  assert.equal(normalizeTitle({ title: '  Node  ' }), 'Node');
  for (const value of [null, {}, { title: '' }, { title: 123 }, { title: 'a'.repeat(81) }]) {
    assert.equal(normalizeTitle(value), null);
  }
});

test('pagination', () => {
  assert.deepEqual(paginate([1, 2, 3], 1, 2), [2, 3]);
  assert.deepEqual(paginate([1], 2, 1), []);
  for (const [offset, limit] of [[-1, 1], [0, 0], [0, 51], [0.5, 3], [null, 20]]) {
    assert.equal(paginate([1], offset, limit), null);
  }
});

test('routing', () => {
  assert.equal(routeStatus('GET', '/tasks'), 200);
  assert.equal(routeStatus('POST', '/tasks'), 201);
  assert.equal(routeStatus('DELETE', '/tasks'), 405);
  assert.equal(routeStatus('GET', '/other'), 404);
});

test('json', () => {
  assert.deepEqual(parseObject('{"title":"Test"}'), { title: 'Test' });
  for (const value of ['null', '3', '[1]', '{']) assert.equal(parseObject(value), null);
});

test('query', () => {
  assert.equal(readInteger(null, 20), 20);
  assert.equal(readInteger('003', 20), 3);
  for (const value of ['', '01.5', '-1', '9007199254740993']) {
    assert.equal(readInteger(value, 20), null);
  }
});

test('addTask', () => {
  const initial = Object.freeze([{ id: 6, title: 'Old' }, { id: 2, title: 'Another' }]);
  assert.deepEqual(addTask(initial, 'New'), [...initial, { id: 7, title: 'New' }]);
  assert.deepEqual(addTask([], 'New'), [{ id: 1, title: 'New' }]);
});

test('HTTP integration', async (t) => {
  const server = createTaskServer().listen(0, '127.0.0.1');
  t.after(() => new Promise((resolve) => {
    server.close(resolve);
    server.closeIdleConnections();
  }));
  await once(server, 'listening');
  const endpoint = 'http://127.0.0.1:' + server.address().port + '/tasks';
  const post = (body) => fetch(endpoint, { method: 'POST', body });
  const created = await post('{"title":"  Deploy "}');
  assert.equal(created.status, 201);
  assert.deepEqual(await created.json(), { id: 1, title: 'Deploy' });
  const list = await fetch(endpoint + '?limit=1');
  assert.equal(list.status, 200);
  assert.deepEqual(await list.json(), { items: [{ id: 1, title: 'Deploy' }], total: 1 });
  for (const [response, status] of [
    [await post('{'), 400],
    [await post('a'.repeat(8193)), 413],
    [await fetch(endpoint + '?limit=abc'), 400],
    [await fetch(endpoint, { method: 'DELETE' }), 405],
    [await fetch(endpoint + '/missing'), 404],
  ]) {
    assert.equal(response.status, status);
    await response.body.cancel();
  }
});

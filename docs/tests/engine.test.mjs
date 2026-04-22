import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateTop, formatResults, normalizeData } from '../src/engine.js';

const rawData = {
  Categories: { Primary: { AR: 0 }, Secondary: {} },
  Penalties: [[1]],
  Data: {
    Cores: [{ Name: 'Core-1', Category: 'AR', Damage: [50, 40], Fire_Rate: 120 }],
    Magazines: [{ Name: 'Mag-1', Category: 'AR', Magazine_Size: 20, Damage: 0, Fire_Rate: 0 }],
    Barrels: [{ Name: 'Barrel-1', Category: 'AR', Damage: 0, Fire_Rate: 0 }],
    Stocks: [{ Name: 'Stock-1', Category: 'AR', Damage: 0, Fire_Rate: 0 }],
    Grips: [{ Name: 'Grip-1', Category: 'AR', Damage: 0, Fire_Rate: 0 }],
  },
};

test('calculateTop returns deterministic single result fixture', () => {
  const data = normalizeData(rawData);
  const results = calculateTop(data, {
    topN: 10,
    playerMaxHealth: 100,
    sortKey: 'ttk',
    priority: 'auto',
    includeCategories: [],
    damageRange: {},
    damageEndRange: {},
    ttkSecondsRange: {},
    dpsRange: {},
  });

  assert.equal(results.length, 1);
  assert.equal(results[0].ttkSeconds, 0.5);
  assert.equal(results[0].dps, 100);
});

test('filters can remove all results', () => {
  const data = normalizeData(rawData);
  const results = calculateTop(data, {
    topN: 10,
    playerMaxHealth: 100,
    sortKey: 'ttk',
    priority: 'auto',
    includeCategories: [],
    damageRange: { min: 9999 },
    damageEndRange: {},
    ttkSecondsRange: {},
    dpsRange: {},
  });

  assert.equal(results.length, 0);
});

test('formatResults renders expected headings', () => {
  const text = formatResults([{ core: 'C', magazine: 'M', barrel: 'B', stock: 'S', grip: 'G', damage: 1, damageEnd: 1, fireRate: 1, ttkSeconds: 1, dps: 1 }]);
  assert.match(text, /#1/);
  assert.match(text, /Core: C/);
});

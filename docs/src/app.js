import { calculateTop, formatResults, normalizeData } from './engine.js';

const output = document.querySelector('#output');
const runBtn = document.querySelector('#runBtn');

runBtn.addEventListener('click', async () => {
  try {
    output.textContent = 'Loading data...';
    const raw = await loadJson(document.querySelector('#dataUrl').value.trim());
    const data = normalizeData(raw);
    const config = readConfig();
    const results = calculateTop(data, config);
    output.textContent = formatResults(results);
  } catch (error) {
    output.textContent = `Error: ${error instanceof Error ? error.message : String(error)}`;
  }
});

function readConfig() {
  return {
    topN: Number(document.querySelector('#topN').value || 10),
    playerMaxHealth: Number(document.querySelector('#maxHealth').value || 100),
    sortKey: document.querySelector('#sortKey').value,
    priority: document.querySelector('#priority').value,
    includeCategories: document.querySelector('#include').value.split(',').map((v) => v.trim()).filter(Boolean),
    partPoolPerType: 20,
    damageRange: {},
    damageEndRange: {},
    ttkSecondsRange: {},
    dpsRange: {},
  };
}

async function loadJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to load data from ${url} (${res.status})`);
  return res.json();
}

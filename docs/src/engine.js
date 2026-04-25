const SORT_KEY = Object.freeze({
  TTK: 'ttk',
  DPS: 'dps',
  DAMAGE: 'damage',
  DAMAGE_END: 'damageend',
  FIRE_RATE: 'firerate',
  MAGAZINE: 'magazine',
});

const PRIORITY = Object.freeze({ HIGHEST: 'highest', LOWEST: 'lowest', AUTO: 'auto' });

export function normalizeData(raw) {
  const categories = {};
  for (const [_, group] of Object.entries(raw.Categories || {})) {
    for (const [name, idx] of Object.entries(group)) categories[name] = Number(idx);
  }

  return {
    cores: (raw.Data?.Cores || []).map((core) => {
      const damage = Array.isArray(core.Damage) ? core.Damage : [core.Damage, core.Damage];
      return {
        name: core.Name,
        category: core.Category,
        damage: Number(damage?.[0] || 0),
        damageEnd: Number(damage?.[1] || 0),
        fireRate: Number(core.Fire_Rate || 0),
      };
    }),
    magazines: (raw.Data?.Magazines || []).map((m) => ({
      name: m.Name,
      category: m.Category,
      magazineSize: Number(m.Magazine_Size || 0),
      damageMod: Number(m.Damage || 0),
      fireRateMod: Number(m.Fire_Rate || 0),
    })),
    barrels: mapPart(raw.Data?.Barrels || []),
    stocks: mapPart(raw.Data?.Stocks || []),
    grips: mapPart(raw.Data?.Grips || []),
    penalties: raw.Penalties || [],
    categories,
  };
}

function mapPart(parts) {
  return parts.map((part) => ({
    name: part.Name,
    category: part.Category,
    damageMod: Number(part.Damage || 0),
    fireRateMod: Number(part.Fire_Rate || 0),
  }));
}

export function calculateTop(data, config) {
  const results = [];
  const partPool = Math.max(1, Number(config.partPoolPerType || 20));

  for (const core of data.cores) {
    if (!includeCategory(config.includeCategories, core.category)) continue;
    const coreIdx = data.categories[core.category];
    if (coreIdx === undefined) continue;

    const mags = topMagazines(data.magazines, core, coreIdx, partPool, data);
    const barrels = topParts(data.barrels, core, coreIdx, partPool, data);
    const stocks = topParts(data.stocks, core, coreIdx, partPool, data);
    const grips = topParts(data.grips, core, coreIdx, partPool, data);

    for (const mag of mags) for (const barrel of barrels) for (const stock of stocks) for (const grip of grips) {
      const result = buildResult(config, data, core, coreIdx, mag, barrel, stock, grip);
      if (!result || !passesFilters(config, result)) continue;
      pushTop(results, result, config);
    }
  }

  return results;
}

function topMagazines(mags, core, coreIdx, limit, data) {
  return [...mags].sort((a, b) => scorePart(core, coreIdx, b, data) - scorePart(core, coreIdx, a, data)).slice(0, limit);
}
function topParts(parts, core, coreIdx, limit, data) {
  return [...parts].sort((a, b) => scorePart(core, coreIdx, b, data) - scorePart(core, coreIdx, a, data)).slice(0, limit);
}
function scorePart(core, coreIdx, part, data) {
  const penalty = penaltyFor(data, coreIdx, part.category);
  return adjustedMod(part.damageMod, core.name, part.name, penalty) + adjustedMod(part.fireRateMod, core.name, part.name, penalty) * 0.6;
}

function buildResult(config, data, core, coreIdx, mag, barrel, stock, grip) {
  const damageMultiplier = percentMultiplier(data, core, coreIdx, [mag, barrel, stock, grip], 'damageMod');
  const fireRateMultiplier = percentMultiplier(data, core, coreIdx, [mag, barrel, stock, grip], 'fireRateMod');

  const damage = core.damage * damageMultiplier;
  const fireRate = core.fireRate * fireRateMultiplier;
  if (damage <= 0 || fireRate <= 0) return null;

  const shots = Math.ceil(Number(config.playerMaxHealth || 100) / damage);
  const ttkSeconds = ((shots - 1) / fireRate) * 60;

  return {
    core: core.name,
    magazine: mag.name,
    barrel: barrel.name,
    stock: stock.name,
    grip: grip.name,
    damage,
    damageEnd: core.damageEnd * damageMultiplier,
    fireRate,
    magazineSize: mag.magazineSize,
    ttkSeconds,
    dps: (damage * fireRate) / 60,
  };
}

function percentMultiplier(data, core, coreIdx, parts, field) {
  return parts.reduce((acc, part) => {
    const penalty = penaltyFor(data, coreIdx, part.category);
    return acc * (1 + adjustedMod(part[field], core.name, part.name, penalty) / 100);
  }, 1);
}

function penaltyFor(data, coreIdx, category) {
  const partIdx = data.categories[category];
  if (partIdx === undefined) return 1;
  return Number(data.penalties?.[coreIdx]?.[partIdx] ?? 1);
}

function adjustedMod(raw, coreName, partName, penalty) {
  return coreName === partName ? 0 : Number(raw || 0) * penalty;
}

function passesFilters(config, result) {
  return inRange(config.damageRange, result.damage)
    && inRange(config.damageEndRange, result.damageEnd)
    && inRange(config.ttkSecondsRange, result.ttkSeconds)
    && inRange(config.dpsRange, result.dps);
}

function inRange(range, value) {
  if (!range) return true;
  if (range.min != null && value < range.min) return false;
  if (range.max != null && value > range.max) return false;
  return true;
}

function includeCategory(allowed, category) {
  return !allowed?.length || allowed.some((c) => c.toLowerCase() === category.toLowerCase());
}

function pushTop(results, candidate, config) {
  const topN = Number(config.topN || 10);
  if (topN <= 0) return;

  if (results.length < topN) {
    results.push(candidate);
  } else if (better(candidate, results[results.length - 1], config)) {
    results[results.length - 1] = candidate;
  } else {
    return;
  }

  results.sort((a, b) => (better(a, b, config) ? -1 : 1));
}

function better(a, b, config) {
  const key = config.sortKey || SORT_KEY.TTK;
  const left = metric(a, key);
  const right = metric(b, key);
  const priority = (config.priority || PRIORITY.AUTO) === PRIORITY.AUTO
    ? (key === SORT_KEY.TTK ? PRIORITY.LOWEST : PRIORITY.HIGHEST)
    : config.priority;

  return priority === PRIORITY.HIGHEST ? left > right : left < right;
}

function metric(result, key) {
  switch (key) {
    case SORT_KEY.DPS: return result.dps;
    case SORT_KEY.DAMAGE: return result.damage;
    case SORT_KEY.DAMAGE_END: return result.damageEnd;
    case SORT_KEY.FIRE_RATE: return result.fireRate;
    case SORT_KEY.MAGAZINE: return result.magazineSize;
    case SORT_KEY.TTK:
    default: return result.ttkSeconds;
  }
}

export function formatResults(results) {
  if (!results.length) return 'No results found.';
  return results.map((r, i) => [
    `#${i + 1}`,
    `Core: ${r.core}`,
    `Magazine: ${r.magazine}`,
    `Barrel: ${r.barrel}`,
    `Stock: ${r.stock}`,
    `Grip: ${r.grip}`,
    `Damage: ${r.damage.toFixed(3)}`,
    `Damage End: ${r.damageEnd.toFixed(3)}`,
    `Fire Rate: ${r.fireRate.toFixed(3)}`,
    `TTK: ${r.ttkSeconds.toFixed(3)}s`,
    `DPS: ${r.dps.toFixed(3)}`,
  ].join('\n')).join('\n\n');
}

export { SORT_KEY, PRIORITY };

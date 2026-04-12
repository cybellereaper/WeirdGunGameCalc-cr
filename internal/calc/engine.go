package calc

import (
	"math"
	"runtime"
	"sort"
	"strings"
	"sync"

	"weirdgungamecalc/internal/model"
)

type Engine struct {
	data model.Dataset
}

type filteredParts struct {
	magazines []model.Part
	barrels   []model.Part
	stocks    []model.Part
	grips     []model.Part
}

func NewEngine(data model.Dataset) *Engine { return &Engine{data: data} }

func (e *Engine) Calculate(opt Options) []model.Gun {
	workerCount := max(1, runtime.NumCPU())
	cores := e.filterCores(opt)
	parts := e.prefilterParts(opt)
	if len(cores) == 0 || len(parts.magazines) == 0 || len(parts.barrels) == 0 || len(parts.stocks) == 0 || len(parts.grips) == 0 {
		return nil
	}

	jobs := make(chan model.Core)
	results := make(chan []model.Gun, workerCount)
	wg := sync.WaitGroup{}

	for i := 0; i < workerCount; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			local := make([]model.Gun, 0, opt.TopN)
			for core := range jobs {
				local = append(local, e.calculateForCore(core, parts, opt)...)
			}
			results <- topN(local, opt.TopN, opt.SortBy, resolveDescending(opt))
		}()
	}

	go func() {
		for _, core := range cores {
			jobs <- core
		}
		close(jobs)
		wg.Wait()
		close(results)
	}()

	merged := make([]model.Gun, 0, opt.TopN*workerCount)
	for chunk := range results {
		merged = append(merged, chunk...)
	}
	return topN(merged, opt.TopN, opt.SortBy, resolveDescending(opt))
}

func (e *Engine) calculateForCore(core model.Core, parts filteredParts, opt Options) []model.Gun {
	result := make([]model.Gun, 0, opt.TopN)
	for _, mag := range parts.magazines {
		for _, barrel := range parts.barrels {
			for _, stock := range parts.stocks {
				for _, grip := range parts.grips {
					gun := buildGun(core, mag, barrel, stock, grip, e.data.Penalties, opt.PlayerMaxHealth)
					if passesFilters(gun, opt.Filters) {
						result = append(result, gun)
					}
				}
			}
		}
	}
	return result
}

func (e *Engine) prefilterParts(opt Options) filteredParts {
	return filteredParts{
		magazines: filterParts(e.data.Magazines, opt.ForceMagazine, opt.BanMagazine, opt.BanPrice),
		barrels:   filterParts(e.data.Barrels, opt.ForceBarrel, opt.BanBarrel, opt.BanPrice),
		stocks:    filterParts(e.data.Stocks, opt.ForceStock, opt.BanStock, opt.BanPrice),
		grips:     filterParts(e.data.Grips, opt.ForceGrip, opt.BanGrip, opt.BanPrice),
	}
}

func filterParts(parts []model.Part, force, ban, banPrice map[string]bool) []model.Part {
	if len(parts) == 0 {
		return nil
	}
	filtered := make([]model.Part, 0, len(parts))
	for _, part := range parts {
		if !partAllowed(part, force, ban, banPrice) {
			continue
		}
		filtered = append(filtered, part)
	}
	return filtered
}

func (e *Engine) filterCores(opt Options) []model.Core {
	cores := make([]model.Core, 0, len(e.data.Cores))
	for _, core := range e.data.Cores {
		if len(opt.Categories) > 0 && !opt.Categories[core.Category] {
			continue
		}
		if len(opt.ForceCore) > 0 && !opt.ForceCore[core.Name] {
			continue
		}
		if opt.BanCore[core.Name] || bannedPrice(core.PriceType, opt.BanPrice) {
			continue
		}
		cores = append(cores, core)
	}
	return cores
}

func partAllowed(part model.Part, force, ban, banPrice map[string]bool) bool {
	if len(force) > 0 && !force[part.Name] {
		return false
	}
	if ban[part.Name] {
		return false
	}
	return !bannedPrice(part.PriceType, banPrice)
}

func bannedPrice(priceType string, banPrice map[string]bool) bool {
	if len(banPrice) == 0 {
		return false
	}
	normalized := strings.ToUpper(priceType)
	switch normalized {
	case "FREE":
		normalized = "COIN"
	case "ROBUX", "WC", "COIN", "LIMITED", "SPECIAL":
	default:
		normalized = "SPECIAL"
	}
	return banPrice[normalized]
}

func getCoreDamage(d any) (float64, float64) {
	switch v := d.(type) {
	case float64:
		return v, v
	case []any:
		if len(v) < 2 {
			return 0, 0
		}
		start, okStart := v[0].(float64)
		end, okEnd := v[1].(float64)
		if okStart && okEnd {
			return start, end
		}
	}
	return 0, 0
}

func buildGun(core model.Core, mag, barrel, stock, grip model.Part, penalties map[string]map[string]float64, maxHealth float64) model.Gun {
	damageStart, damageEnd := getCoreDamage(core.Damage)
	falloffFactor := calculateFalloffFactor(damageStart, damageEnd)

	gun := initGun(core, mag, barrel, stock, grip, damageStart)
	parts := []model.Part{mag, barrel, stock, grip}
	for _, part := range parts {
		penalty := partPenalty(penalties, core.Category, part.Category, core.Name == part.Name)
		gun, falloffFactor = applyPart(gun, part, penalty, falloffFactor)
	}

	finalizeGunStats(&gun, falloffFactor, maxHealth)
	return gun
}

func calculateFalloffFactor(damageStart, damageEnd float64) float64 {
	if damageStart == 0 {
		return 0
	}
	return (damageEnd - damageStart) / damageStart
}

func initGun(core model.Core, mag, barrel, stock, grip model.Part, damageStart float64) model.Gun {
	return model.Gun{
		Core:            core.Name,
		Barrel:          barrel.Name,
		Magazine:        mag.Name,
		Grip:            grip.Name,
		Stock:           stock.Name,
		Category:        core.Category,
		Damage:          damageStart,
		DropoffStart:    core.DropoffStuds[0],
		DropoffEnd:      core.DropoffStuds[1],
		FireRate:        core.FireRate,
		Pellets:         positiveOrOne(core.Pellets),
		SpreadHip:       core.HipfireSpread,
		SpreadAim:       core.ADSSpread,
		RecoilHip:       core.RecoilHipVertical[1],
		RecoilAim:       core.RecoilAimVertical[1],
		TimeToAim:       core.TimeToAim,
		ReloadTime:      mag.ReloadTime,
		MagazineSize:    mag.MagazineSize,
		MovementSpeed:   core.MovementSpeedMod,
		Health:          core.Health,
		DetectionRadius: core.DetectionRadius,
		Burst:           positiveOrOne(core.Burst),
	}
}

func applyPart(g model.Gun, part model.Part, penalty, falloffFactor float64) (model.Gun, float64) {
	g.Pellets = math.Ceil(g.Pellets * percentToMultiplier(part.Pellets, penalty))
	g.Damage *= percentToMultiplier(part.Damage, penalty)
	g.FireRate *= percentToMultiplier(part.FireRate, penalty)
	g.SpreadAim *= percentToMultiplier(part.Spread, penalty)
	g.SpreadHip *= percentToMultiplier(part.Spread, penalty)
	g.RecoilAim *= percentToMultiplier(part.Recoil, penalty)
	g.RecoilHip *= percentToMultiplier(part.Recoil, penalty)
	g.ReloadTime *= percentToMultiplier(part.ReloadSpeed, penalty)
	g.MagazineSize = round(g.MagazineSize * percentToMultiplier(part.MagazineCap, penalty))
	g.MovementSpeed += part.MovementSpeed * penalty
	g.Health += part.Health * penalty
	g.DetectionRadius *= percentToMultiplier(part.DetectionRadius, penalty)
	g.DropoffStart *= percentToMultiplier(part.Range, penalty)
	g.DropoffEnd *= percentToMultiplier(part.Range, penalty)
	falloffFactor *= 1 - ((part.Range * penalty) / 100)
	return g, falloffFactor
}

func percentToMultiplier(statModifierPercent, penalty float64) float64 {
	return 1 + ((statModifierPercent * penalty) / 100)
}

func finalizeGunStats(g *model.Gun, falloffFactor, maxHealth float64) {
	g.DamageEnd = g.Damage + (g.Damage * falloffFactor)
	g.DPM = g.Damage * g.FireRate
	g.DPS = g.DPM / 60
	if g.Damage <= 0 || g.FireRate <= 0 {
		g.TTKMinutes = math.Inf(1)
		g.TTKSeconds = math.Inf(1)
		return
	}
	g.TTKMinutes = (math.Ceil(maxHealth/g.Damage) - 1) / g.FireRate
	g.TTKSeconds = g.TTKMinutes * 60
}

func positiveOrOne(v float64) float64 {
	if v <= 0 {
		return 1
	}
	return v
}

func partPenalty(penalties map[string]map[string]float64, coreCategory, partCategory string, sameName bool) float64 {
	if sameName {
		return 0
	}
	if penalties[coreCategory] == nil {
		return 1
	}
	if p, ok := penalties[coreCategory][partCategory]; ok {
		return p
	}
	return 1
}

func topN(guns []model.Gun, n int, sortBy SortBy, desc bool) []model.Gun {
	if n <= 0 || len(guns) == 0 {
		return nil
	}
	sort.Slice(guns, func(i, j int) bool {
		a := metric(guns[i], sortBy)
		b := metric(guns[j], sortBy)
		if desc {
			return a > b
		}
		return a < b
	})
	if len(guns) > n {
		return guns[:n]
	}
	return guns
}

func metric(g model.Gun, by SortBy) float64 {
	switch by {
	case SortDamage:
		return g.Damage
	case SortDamageEnd:
		return g.DamageEnd
	case SortFireRate:
		return g.FireRate
	case SortPellets:
		return g.Pellets
	case SortSpreadAim:
		return g.SpreadAim
	case SortSpreadHip:
		return g.SpreadHip
	case SortRecoilAim:
		return g.RecoilAim
	case SortRecoilHip:
		return g.RecoilHip
	case SortHealth:
		return g.Health
	case SortRange:
		return g.DropoffStart
	case SortRangeEnd:
		return g.DropoffEnd
	case SortDetectRadius:
		return g.DetectionRadius
	case SortTimeToAim:
		return g.TimeToAim
	case SortBurst:
		return g.Burst
	case SortSpeed:
		return g.MovementSpeed
	case SortMagazine:
		return g.MagazineSize
	case SortReload:
		return g.ReloadTime
	case SortDPS:
		return g.DPM
	default:
		return g.TTKMinutes
	}
}

func passesFilters(g model.Gun, f Filters) bool {
	return f.Damage.Contains(g.Damage) &&
		f.DamageEnd.Contains(g.DamageEnd) &&
		f.Magazine.Contains(g.MagazineSize) &&
		f.SpreadHip.Contains(g.SpreadHip) &&
		f.SpreadAim.Contains(g.SpreadAim) &&
		f.RecoilHip.Contains(g.RecoilHip) &&
		f.RecoilAim.Contains(g.RecoilAim) &&
		f.Speed.Contains(g.MovementSpeed) &&
		f.FireRate.Contains(g.FireRate) &&
		f.Health.Contains(g.Health) &&
		f.Pellets.Contains(g.Pellets) &&
		f.TimeToAim.Contains(g.TimeToAim) &&
		f.Reload.Contains(g.ReloadTime) &&
		f.DetectionRadius.Contains(g.DetectionRadius) &&
		f.RangeStart.Contains(g.DropoffStart) &&
		f.RangeEnd.Contains(g.DropoffEnd) &&
		f.Burst.Contains(g.Burst) &&
		f.TTK.Contains(g.TTKMinutes) &&
		f.DPS.Contains(g.DPM)
}

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

func NewEngine(data model.Dataset) *Engine { return &Engine{data: data} }

func (e *Engine) Calculate(opt Options) []model.Gun {
	workerCount := runtime.NumCPU()
	if workerCount < 1 {
		workerCount = 1
	}

	cores := e.filterCores(opt)
	jobs := make(chan model.Core)
	results := make(chan []model.Gun, workerCount)
	wg := sync.WaitGroup{}

	for i := 0; i < workerCount; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			local := make([]model.Gun, 0, opt.TopN)
			for core := range jobs {
				for _, mag := range e.data.Magazines {
					if !partAllowed(mag, opt.ForceMagazine, opt.BanMagazine, opt.BanPrice) {
						continue
					}
					for _, barrel := range e.data.Barrels {
						if !partAllowed(barrel, opt.ForceBarrel, opt.BanBarrel, opt.BanPrice) {
							continue
						}
						for _, stock := range e.data.Stocks {
							if !partAllowed(stock, opt.ForceStock, opt.BanStock, opt.BanPrice) {
								continue
							}
							for _, grip := range e.data.Grips {
								if !partAllowed(grip, opt.ForceGrip, opt.BanGrip, opt.BanPrice) {
									continue
								}
								gun := buildGun(core, mag, barrel, stock, grip, e.data.Penalties, opt.PlayerMaxHealth)
								if passesFilters(gun, opt.Filters) {
									local = append(local, gun)
								}
							}
						}
					}
				}
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

func (e *Engine) filterCores(opt Options) []model.Core {
	cores := make([]model.Core, 0, len(e.data.Cores))
	for _, core := range e.data.Cores {
		if len(opt.Categories) > 0 && !opt.Categories[core.Category] {
			continue
		}
		if len(opt.ForceCore) > 0 && !opt.ForceCore[core.Name] {
			continue
		}
		if opt.BanCore[core.Name] {
			continue
		}
		if bannedPrice(core.PriceType, opt.BanPrice) {
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
	case "ROBUX":
	case "WC", "COIN", "LIMITED", "SPECIAL":
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
		if len(v) >= 2 {
			a, aok := v[0].(float64)
			b, bok := v[1].(float64)
			if aok && bok {
				return a, b
			}
		}
	}
	return 0, 0
}

func buildGun(core model.Core, mag, barrel, stock, grip model.Part, penalties map[string]map[string]float64, maxHealth float64) model.Gun {
	damageStart, damageEnd := getCoreDamage(core.Damage)
	falloffFactor := 0.0
	if damageStart != 0 {
		falloffFactor = (damageEnd - damageStart) / damageStart
	}

	gun := model.Gun{
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

	parts := []model.Part{mag, barrel, stock, grip}
	for _, p := range parts {
		pen := partPenalty(penalties, core.Category, p.Category, core.Name == p.Name)
		gun.Pellets = math.Ceil(gun.Pellets * (1 + ((p.Pellets * pen) / 100)))
		gun.Damage *= 1 + ((p.Damage * pen) / 100)
		gun.FireRate *= 1 + ((p.FireRate * pen) / 100)
		gun.SpreadAim *= 1 + ((p.Spread * pen) / 100)
		gun.SpreadHip *= 1 + ((p.Spread * pen) / 100)
		gun.RecoilAim *= 1 + ((p.Recoil * pen) / 100)
		gun.RecoilHip *= 1 + ((p.Recoil * pen) / 100)
		gun.ReloadTime *= 1 + ((p.ReloadSpeed * pen) / 100)
		gun.MagazineSize = round(gun.MagazineSize * (1 + ((p.MagazineCap * pen) / 100)))
		gun.MovementSpeed += p.MovementSpeed * pen
		gun.Health += p.Health * pen
		gun.DetectionRadius *= 1 + ((p.DetectionRadius * pen) / 100)
		gun.DropoffStart *= 1 + ((p.Range * pen) / 100)
		gun.DropoffEnd *= 1 + ((p.Range * pen) / 100)
		falloffFactor *= 1 - ((p.Range * pen) / 100)
	}

	gun.DamageEnd = gun.Damage + (gun.Damage * falloffFactor)
	gun.DPM = gun.Damage * gun.FireRate
	gun.DPS = gun.DPM / 60
	if gun.Damage <= 0 || gun.FireRate <= 0 {
		gun.TTKMinutes = math.Inf(1)
		gun.TTKSeconds = math.Inf(1)
	} else {
		gun.TTKMinutes = (math.Ceil(maxHealth/gun.Damage) - 1) / gun.FireRate
		gun.TTKSeconds = gun.TTKMinutes * 60
	}
	return gun
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

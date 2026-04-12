package calc

import (
	"math"
	"testing"

	"weirdgungamecalc/internal/model"
)

func TestBuildGunBaseline(t *testing.T) {
	core := model.Core{Name: "Core", Category: "AR", Damage: 25.0, FireRate: 600, HipfireSpread: 1, ADSSpread: 1, TimeToAim: 0.2, DetectionRadius: 100, Pellets: 1, Burst: 1, DropoffStuds: [2]float64{100, 200}}
	mag := model.Part{Name: "Mag", Category: "AR", MagazineSize: 30, ReloadTime: 2}
	barrel := model.Part{Name: "Barrel", Category: "AR"}
	stock := model.Part{Name: "Stock", Category: "AR"}
	grip := model.Part{Name: "Grip", Category: "AR"}

	g := buildGun(core, mag, barrel, stock, grip, nil, 100)

	if g.TTKMinutes <= 0 {
		t.Fatalf("expected positive ttk, got %v", g.TTKMinutes)
	}
	if g.Damage != 25 {
		t.Fatalf("expected damage 25, got %v", g.Damage)
	}
	if g.DPM != 15000 {
		t.Fatalf("expected dpm 15000, got %v", g.DPM)
	}
}

func TestBuildGunHandlesArrayDamage(t *testing.T) {
	core := model.Core{Name: "Core", Category: "AR", Damage: []any{20.0, 10.0}, FireRate: 300, Pellets: 1, Burst: 1, DropoffStuds: [2]float64{80, 160}}
	mag := model.Part{Name: "Mag", Category: "AR", MagazineSize: 20, ReloadTime: 2}
	g := buildGun(core, mag, model.Part{}, model.Part{}, model.Part{}, nil, 100)

	if g.Damage != 20 {
		t.Fatalf("expected start damage 20 got %v", g.Damage)
	}
	if g.DamageEnd != 10 {
		t.Fatalf("expected end damage 10 got %v", g.DamageEnd)
	}
}

func TestFinalizeGunStatsInfiniteTTK(t *testing.T) {
	g := model.Gun{Damage: 0, FireRate: 100}
	finalizeGunStats(&g, 0, 100)
	if !math.IsInf(g.TTKMinutes, 1) {
		t.Fatalf("expected infinite TTKMinutes got %v", g.TTKMinutes)
	}
}

func TestPassesFilters(t *testing.T) {
	g := model.Gun{Damage: 10, DamageEnd: 8, MagazineSize: 12, SpreadHip: 1, SpreadAim: 1, RecoilHip: 1, RecoilAim: 1, MovementSpeed: 0, FireRate: 100, Health: 0, Pellets: 1, TimeToAim: 0.2, ReloadTime: 2, DetectionRadius: 10, DropoffStart: 50, DropoffEnd: 100, Burst: 1, TTKMinutes: 0.1, DPM: 1000}
	f := DefaultOptions().Filters
	f.Damage = Range{Min: 9, Max: 11}
	f.TTK = Range{Min: 0, Max: 1}
	if !passesFilters(g, f) {
		t.Fatal("expected gun to pass filters")
	}
	f.Damage = Range{Min: 11, Max: 20}
	if passesFilters(g, f) {
		t.Fatal("expected gun to fail damage filter")
	}
}

func TestTopNSortByTTK(t *testing.T) {
	guns := []model.Gun{{Core: "A", TTKMinutes: 0.4}, {Core: "B", TTKMinutes: 0.2}, {Core: "C", TTKMinutes: 0.3}}
	got := topN(guns, 2, SortTTK, false)
	if len(got) != 2 {
		t.Fatalf("expected 2 got %d", len(got))
	}
	if got[0].Core != "B" || got[1].Core != "C" {
		t.Fatalf("unexpected order: %+v", got)
	}
}

func TestBannedPriceFreeAsCoin(t *testing.T) {
	ban := map[string]bool{"COIN": true}
	if !bannedPrice("Free", ban) {
		t.Fatal("expected Free to map to COIN and be banned")
	}
}

func TestTopCollectorKeepsBoundedResultsDescending(t *testing.T) {
	collector := newTopCollector(2, SortDamage, true)
	collector.Push(model.Gun{Core: "A", Damage: 10})
	collector.Push(model.Gun{Core: "B", Damage: 20})
	collector.Push(model.Gun{Core: "C", Damage: 15})

	got := collector.Results()
	if len(got) != 2 {
		t.Fatalf("expected 2 results, got %d", len(got))
	}
	if got[0].Core != "B" || got[1].Core != "C" {
		t.Fatalf("unexpected top order: %+v", got)
	}
}

func TestTopCollectorKeepsBoundedResultsAscending(t *testing.T) {
	collector := newTopCollector(2, SortTTK, false)
	collector.Push(model.Gun{Core: "A", TTKMinutes: 0.4})
	collector.Push(model.Gun{Core: "B", TTKMinutes: 0.2})
	collector.Push(model.Gun{Core: "C", TTKMinutes: 0.3})

	got := collector.Results()
	if len(got) != 2 {
		t.Fatalf("expected 2 results, got %d", len(got))
	}
	if got[0].Core != "B" || got[1].Core != "C" {
		t.Fatalf("unexpected top order: %+v", got)
	}
}

func TestEstimateSearchSpaceRespectsFiltering(t *testing.T) {
	engine := NewEngine(model.Dataset{
		Cores:     []model.Core{{Name: "CoreA", Category: "AR"}, {Name: "CoreB", Category: "SMG"}},
		Magazines: []model.Part{{Name: "M1"}, {Name: "M2"}},
		Barrels:   []model.Part{{Name: "B1"}},
		Stocks:    []model.Part{{Name: "S1"}},
		Grips:     []model.Part{{Name: "G1"}},
	})

	opt := DefaultOptions()
	opt.Categories = map[string]bool{"AR": true}
	opt.ForceMagazine = map[string]bool{"M1": true}

	estimated := engine.EstimateSearchSpace(opt)
	if estimated != 1 {
		t.Fatalf("expected 1 estimated combination, got %d", estimated)
	}
}

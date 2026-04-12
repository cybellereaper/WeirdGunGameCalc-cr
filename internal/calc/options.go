package calc

import "math"

type SortBy string

const (
	SortTTK          SortBy = "TTK"
	SortDamage       SortBy = "DAMAGE"
	SortDamageEnd    SortBy = "DAMAGEEND"
	SortFireRate     SortBy = "FIRERATE"
	SortPellets      SortBy = "PELLETS"
	SortSpreadAim    SortBy = "SPREADAIM"
	SortSpreadHip    SortBy = "SPREADHIP"
	SortRecoilAim    SortBy = "RECOILAIM"
	SortRecoilHip    SortBy = "RECOILHIP"
	SortHealth       SortBy = "HEALTH"
	SortRange        SortBy = "RANGE"
	SortRangeEnd     SortBy = "RANGEEND"
	SortDetectRadius SortBy = "DETECTIONRADIUS"
	SortTimeToAim    SortBy = "TIMETOAIM"
	SortBurst        SortBy = "BURST"
	SortSpeed        SortBy = "SPEED"
	SortMagazine     SortBy = "MAGAZINE"
	SortReload       SortBy = "RELOAD"
	SortDPS          SortBy = "DPS"
)

type Range struct {
	Min float64
	Max float64
}

func NewAnyRange() Range { return Range{Min: -69420.5, Max: 69420.5} }

func (r Range) Contains(v float64) bool {
	return v >= r.Min && v <= r.Max
}

type Filters struct {
	Damage          Range
	DamageEnd       Range
	Magazine        Range
	SpreadHip       Range
	SpreadAim       Range
	RecoilHip       Range
	RecoilAim       Range
	Speed           Range
	FireRate        Range
	Health          Range
	Pellets         Range
	TimeToAim       Range
	Reload          Range
	DetectionRadius Range
	RangeStart      Range
	RangeEnd        Range
	Burst           Range
	TTK             Range
	DPS             Range
}

type Options struct {
	TopN            int
	SortBy          SortBy
	Descending      *bool
	PlayerMaxHealth float64
	Categories      map[string]bool

	ForceCore     map[string]bool
	ForceBarrel   map[string]bool
	ForceMagazine map[string]bool
	ForceGrip     map[string]bool
	ForceStock    map[string]bool

	BanCore     map[string]bool
	BanBarrel   map[string]bool
	BanMagazine map[string]bool
	BanGrip     map[string]bool
	BanStock    map[string]bool
	BanPrice    map[string]bool

	Filters Filters
}

func DefaultOptions() Options {
	return Options{
		TopN:            10,
		SortBy:          SortTTK,
		Descending:      nil,
		PlayerMaxHealth: 100,
		Categories:      map[string]bool{},
		ForceCore:       map[string]bool{},
		ForceBarrel:     map[string]bool{},
		ForceMagazine:   map[string]bool{},
		ForceGrip:       map[string]bool{},
		ForceStock:      map[string]bool{},
		BanCore:         map[string]bool{},
		BanBarrel:       map[string]bool{},
		BanMagazine:     map[string]bool{},
		BanGrip:         map[string]bool{},
		BanStock:        map[string]bool{},
		BanPrice:        map[string]bool{},
		Filters: Filters{
			Damage:          NewAnyRange(),
			DamageEnd:       NewAnyRange(),
			Magazine:        NewAnyRange(),
			SpreadHip:       NewAnyRange(),
			SpreadAim:       NewAnyRange(),
			RecoilHip:       NewAnyRange(),
			RecoilAim:       NewAnyRange(),
			Speed:           NewAnyRange(),
			FireRate:        NewAnyRange(),
			Health:          NewAnyRange(),
			Pellets:         NewAnyRange(),
			TimeToAim:       NewAnyRange(),
			Reload:          NewAnyRange(),
			DetectionRadius: NewAnyRange(),
			RangeStart:      NewAnyRange(),
			RangeEnd:        NewAnyRange(),
			Burst:           NewAnyRange(),
			TTK:             NewAnyRange(),
			DPS:             NewAnyRange(),
		},
	}
}

func moreIsBetter(sortBy SortBy) bool {
	switch sortBy {
	case SortTTK, SortSpreadAim, SortSpreadHip, SortRecoilAim, SortRecoilHip, SortTimeToAim, SortReload, SortDetectRadius, SortBurst:
		return false
	default:
		return true
	}
}

func resolveDescending(opt Options) bool {
	if opt.Descending != nil {
		return *opt.Descending
	}
	return moreIsBetter(opt.SortBy)
}

func round(v float64) float64 {
	if v >= 0 {
		return math.Floor(v + 0.5)
	}
	return math.Ceil(v - 0.5)
}

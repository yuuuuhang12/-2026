# 200_stab MATLAB analysis

Main script:

```matlab
02 Work/02 Реализация/01 scripts/analyze_200_stab.m
```

Run from MATLAB:

```matlab
cd("D:\学习资料\电子资料\Радиотехника 大学本科课程\03 НИР и практикум 科研与实习\Летний практикум 2026\02 Work\02 Реализация\01 scripts")
analyze_200_stab
```

The script reads:

- `02 Work/01 Задание/200_magn_stab.txt`
- `02 Work/01 Задание/200_lla_stab.csv`

It writes:

- `02 Work/03 Результат/figures/magnetic_field_norm_200_stab.png`
- `02 Work/03 Результат/figures/ground_track_altitude_200_stab.png`
- `02 Work/03 Результат/tables/cleaning_stats_200_stab.csv`
- `02 Work/03 Результат/tables/time_stats_200_stab.csv`
- `02 Work/03 Результат/tables/axis_quality_200_stab.csv`
- `02 Work/03 Результат/tables/magnetic_norm_stats_200_stab.csv`
- `02 Work/03 Результат/tables/diff_spike_stats_200_stab.csv`
- `02 Work/03 Результат/tables/sync_stats_200_stab.csv`
- `02 Work/03 Результат/tables/orbit_period_200_stab.csv`
- `02 Work/03 Результат/analysis_summary_200_stab.txt`

Expected validation values:

- inferred magnetometer time unit: `ms`
- most common sampling interval: about `10 ms`
- usable magnetometer rows: about `1,096,027`
- valid navigation rows: `708`
- `|B|` mean: about `380.77 mGs`
- `|B|` std: about `127.82 mGs`
- `|B|` min: about `70.26 mGs`
- `|B|` max: about `665.18 mGs`
- most navigation points should match magnetometer time within `10 ms`
- orbit period from positive latitude maxima: about `94 min`

Notes:

- The altitude-time plot is intentionally not generated.
- Altitude is encoded as color in the ground-track figure.
- Difference-based 3-sigma spikes are counted and reported, but not removed.
- In this Codex environment MATLAB failed at startup with `System Error: File system inconsistency`, so the script was not run here. Run it in the normal MATLAB desktop if the command-line batch mode fails.

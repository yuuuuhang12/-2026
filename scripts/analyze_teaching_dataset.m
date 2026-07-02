%% Analysis of raw-like teaching semi-synthetic satellite dataset
% The script reads student-facing files that mimic the original task data:
%   teaching_dataset/raw_like/teaching_magn_semisynth.txt
%   teaching_dataset/raw_like/teaching_lla_semisynth.csv
%
% It computes magnetic-field modulus and builds report figures:
%   |B| over time
%   longitude-latitude track colored by altitude
%   longitude-latitude track colored by magnetic-field modulus

clear; clc; close all;

%% Paths
scriptDir = fileparts(mfilename("fullpath"));
repoDir = fileparts(scriptDir);
datasetDir = fullfile(repoDir, "teaching_dataset");
rawLikeDir = fullfile(datasetDir, "raw_like");
processedDir = fullfile(datasetDir, "processed");
figureDir = fullfile(datasetDir, "figures");

if ~exist(processedDir, "dir"); mkdir(processedDir); end
if ~exist(figureDir, "dir"); mkdir(figureDir); end

magFile = fullfile(rawLikeDir, "teaching_magn_semisynth.txt");
navFile = fullfile(rawLikeDir, "teaching_lla_semisynth.csv");

if ~isfile(magFile)
    error("Не найден файл магнитометра: %s. Сначала выполните generate_teaching_dataset.", magFile);
end
if ~isfile(navFile)
    error("Не найден файл навигации: %s. Сначала выполните generate_teaching_dataset.", navFile);
end

%% Magnetometer data
fprintf("Чтение учебного файла магнитометра: %s\n", magFile);
magRaw = readmatrix(magFile, "FileType", "text");

rawRows = size(magRaw, 1);
validNumeric = all(isfinite(magRaw), 2);
invalidNumericRows = sum(~validNumeric);

timeMsAll = magRaw(:, 1);
BxyzAll = magRaw(:, 2:4);
zeroTimeRows = sum(validNumeric & timeMsAll == 0);
zeroVectorRows = sum(validNumeric & all(BxyzAll == 0, 2));

validForMagneticNorm = validNumeric & timeMsAll > 0;
timeMs = timeMsAll(validForMagneticNorm);
Bx = BxyzAll(validForMagneticNorm, 1);
By = BxyzAll(validForMagneticNorm, 2);
Bz = BxyzAll(validForMagneticNorm, 3);
Bnorm = sqrt(Bx.^2 + By.^2 + Bz.^2);
magTime = datetime(timeMs / 1000, "ConvertFrom", "posixtime", "TimeZone", "UTC");

magneticStats = table( ...
    rawRows, invalidNumericRows, zeroTimeRows, zeroVectorRows, numel(Bnorm), ...
    mean(Bnorm, "omitnan"), std(Bnorm, 1, "omitnan"), min(Bnorm), max(Bnorm), ...
    'VariableNames', ["raw_rows", "nan_or_non_numeric_rows", "zero_time_rows", ...
    "zero_vector_rows", "rows_used_for_magnetic_norm", ...
    "B_norm_mean_mGs", "B_norm_std_mGs", "B_norm_min_mGs", "B_norm_max_mGs"]);
writetable(magneticStats, fullfile(processedDir, "magnetic_norm_stats_teaching.csv"));

%% Navigation data
fprintf("Чтение учебного файла навигации: %s\n", navFile);
nav = readTeachingNavigationCsv(navFile);
validNav = isfinite(nav.timeMs) & isfinite(nav.altitudeM) & ...
    isfinite(nav.latitudeDeg) & isfinite(nav.longitudeDeg);
nav = nav(validNav, :);

%% Synchronization for magnetic-color ground track
fprintf("Сопоставление навигации с магнитометром методом ближайшего соседа...\n");
validNavForSync = nav.timeMs > 0;
navForMagneticTrack = nav(validNavForSync, :);
[nearestMagIndex, syncErrorMs] = nearestNeighbor(timeMs, navForMagneticTrack.timeMs);
navBnorm = Bnorm(nearestMagIndex);

syncStats = table( ...
    min(syncErrorMs), median(syncErrorMs), max(syncErrorMs), ...
    sum(syncErrorMs <= 10000), numel(syncErrorMs), sum(~validNavForSync), ...
    'VariableNames', ["sync_error_min_ms", "sync_error_median_ms", "sync_error_max_ms", ...
    "points_matched_within_10_s", "navigation_points_used", "navigation_points_with_zero_time"]);
writetable(syncStats, fullfile(processedDir, "sync_stats_teaching.csv"));

fprintf("Построение графиков учебного набора данных...\n");
plotMagneticNorm(magTime, Bnorm, figureDir);
plotGroundTrackAltitude(nav.longitudeDeg, nav.latitudeDeg, nav.altitudeM, figureDir);
plotGroundTrackMagneticNorm(navForMagneticTrack.longitudeDeg, navForMagneticTrack.latitudeDeg, navBnorm, figureDir);

fprintf("\nАнализ учебного набора данных завершен.\n");
fprintf("Таблицы: %s\n", processedDir);
fprintf("Графики: %s\n", figureDir);

%% Local functions

function nav = readTeachingNavigationCsv(navFile)
    rawLines = readlines(navFile);
    rawLines = rawLines(strlength(strtrim(rawLines)) > 0);
    dataLines = rawLines(2:end);

    rtc = strings(0, 1);
    timeMs = [];
    altitudeM = [];
    latitudeDeg = [];
    longitudeDeg = [];

    for i = 1:numel(dataLines)
        parts = split(dataLines(i), ";");
        if numel(parts) < 5
            continue;
        end

        rtcText = strtrim(parts(1));
        timeText = strtrim(parts(2));
        altText = strtrim(parts(3));
        latText = strtrim(parts(4));
        lonText = strtrim(parts(5));

        parsedTime = str2double(strrep(timeText, ",", "."));
        parsedAlt = str2double(strrep(altText, ",", "."));
        parsedLat = str2double(strrep(latText, ",", "."));
        parsedLon = str2double(strrep(lonText, ",", "."));

        rtc(end + 1, 1) = rtcText; %#ok<AGROW>
        timeMs(end + 1, 1) = parsedTime; %#ok<AGROW>
        altitudeM(end + 1, 1) = parsedAlt; %#ok<AGROW>
        latitudeDeg(end + 1, 1) = parsedLat; %#ok<AGROW>
        longitudeDeg(end + 1, 1) = parsedLon; %#ok<AGROW>
    end

    nav = table(rtc, timeMs, altitudeM, latitudeDeg, longitudeDeg);
end

function [nearestIndex, syncErrorMs] = nearestNeighbor(sourceTimeMs, queryTimeMs)
    nearestIndex = zeros(size(queryTimeMs));
    syncErrorMs = zeros(size(queryTimeMs));

    for i = 1:numel(queryTimeMs)
        [syncErrorMs(i), nearestIndex(i)] = min(abs(sourceTimeMs - queryTimeMs(i)));
    end
end

function plotMagneticNorm(magTime, Bnorm, figureDir)
    fig = figure("Visible", "off", "Color", "w", "Position", [100 100 1200 520]);
    plot(magTime, Bnorm, "Color", [0.05 0.25 0.55], "LineWidth", 0.8);
    xlabel("Время, UTC");
    ylabel("|B|, мГс");
    title("Модуль магнитного поля учебного набора данных");
    subtitle(sprintf("Среднее %.2f мГс, СКО %.2f мГс", mean(Bnorm, "omitnan"), std(Bnorm, 1, "omitnan")));
    legend("|B|", "Location", "best");
    grid on;
    exportgraphics(fig, fullfile(figureDir, "teaching_magnetic_norm.png"), "Resolution", 300);
    close(fig);
end

function plotGroundTrackAltitude(lonDeg, latDeg, altM, figureDir)
    fig = figure("Visible", "off", "Color", "w", "Position", [120 120 1100 620]);
    drawWorldMapBackground();
    hold on;
    scatter(lonDeg, latDeg, 28, altM / 1000, "filled");
    xlabel("Долгота, град");
    ylabel("Широта, град");
    title("Наземный трек учебного набора данных: цветом показана высота");
    cb = colorbar;
    cb.Label.String = "Высота, км";
    colormap(turbo);
    plot(lonDeg(1), latDeg(1), "go", "MarkerFaceColor", "g", "MarkerSize", 7);
    plot(lonDeg(end), latDeg(end), "rs", "MarkerFaceColor", "r", "MarkerSize", 7);
    legend({"Точки трека", "Начало", "Конец"}, "Location", "southoutside", "Orientation", "horizontal");
    formatWorldMapAxes();
    exportgraphics(fig, fullfile(figureDir, "teaching_ground_track_altitude.png"), "Resolution", 300);
    close(fig);
end

function plotGroundTrackMagneticNorm(lonDeg, latDeg, Bnorm, figureDir)
    fig = figure("Visible", "off", "Color", "w", "Position", [120 120 1100 620]);
    drawWorldMapBackground();
    hold on;
    scatter(lonDeg, latDeg, 28, Bnorm, "filled");
    xlabel("Долгота, град");
    ylabel("Широта, град");
    title("Наземный трек учебного набора данных: цветом показан модуль магнитного поля");
    cb = colorbar;
    cb.Label.String = "|B|, мГс";
    colormap(turbo);
    plot(lonDeg(1), latDeg(1), "go", "MarkerFaceColor", "g", "MarkerSize", 7);
    plot(lonDeg(end), latDeg(end), "rs", "MarkerFaceColor", "r", "MarkerSize", 7);
    legend({"Точки трека", "Начало", "Конец"}, "Location", "southoutside", "Orientation", "horizontal");
    formatWorldMapAxes();
    exportgraphics(fig, fullfile(figureDir, "teaching_ground_track_magnetic_norm.png"), "Resolution", 300);
    close(fig);
end

function drawWorldMapBackground()
    try
        coast = load("coastlines");
        plot(coast.coastlon, coast.coastlat, "Color", [0.68 0.68 0.68], "LineWidth", 0.5);
    catch
        fprintf("Предупреждение: данные coastlines недоступны; фон карты мира пропущен.\n");
    end
end

function formatWorldMapAxes()
    xlim([-180 180]);
    ylim([-90 90]);
    pbaspect([2 1 1]);
    grid on;
    box on;
end

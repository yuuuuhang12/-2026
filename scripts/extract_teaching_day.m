%% Extract one day from the teaching semi-synthetic dataset
% Default target day: 2026-05-11.
% Outputs:
%   teaching_dataset/processed/teaching_day_2026_05_11.csv
%   teaching_dataset/figures/teaching_day_2026_05_11_ground_track.png
%   teaching_dataset/figures/teaching_day_2026_05_11_magnetic_norm.png
%   teaching_dataset/figures/teaching_day_2026_05_11_ground_track_magnetic_norm.png

clear; clc; close all;

targetDay = datetime(2026, 5, 11, "TimeZone", "UTC");
targetTag = string(targetDay, "yyyy_MM_dd");

scriptDir = fileparts(mfilename("fullpath"));
repoDir = fileparts(scriptDir);
datasetDir = fullfile(repoDir, "teaching_dataset");
dataFile = fullfile(datasetDir, "data", "teaching_satellite_dataset.csv");
processedDir = fullfile(datasetDir, "processed");
figureDir = fullfile(datasetDir, "figures");

if ~exist(processedDir, "dir"); mkdir(processedDir); end
if ~exist(figureDir, "dir"); mkdir(figureDir); end
if ~isfile(dataFile)
    error("Не найден файл данных: %s. Сначала выполните generate_teaching_dataset.", dataFile);
end

fprintf("Чтение учебного набора данных: %s\n", dataFile);
data = readtable(dataFile, "TextType", "string");
timestampUtc = datetime(data.timestamp_utc, "InputFormat", "yyyy-MM-dd HH:mm:ss", "TimeZone", "UTC");

dayMask = timestampUtc >= targetDay & timestampUtc < targetDay + days(1);
dayData = data(dayMask, :);
dayTime = timestampUtc(dayMask);

if isempty(dayData)
    error("Нет данных за выбранную дату: %s.", string(targetDay, "yyyy-MM-dd"));
end

fprintf("Найдено строк за %s: %d\n", string(targetDay, "yyyy-MM-dd"), height(dayData));

outCsv = fullfile(processedDir, "teaching_day_" + targetTag + ".csv");
writetable(dayData, outCsv);

plotDayGroundTrack(dayData, targetDay, figureDir, targetTag);
plotDayMagneticNorm(dayData, dayTime, targetDay, figureDir, targetTag);
plotDayGroundTrackMagneticNorm(dayData, targetDay, figureDir, targetTag);

fprintf("Файл данных за день: %s\n", outCsv);
fprintf("Графики сохранены в: %s\n", figureDir);

%% Local functions

function plotDayGroundTrack(dayData, targetDay, figureDir, targetTag)
    fig = figure("Visible", "off", "Color", "w", "Position", [100 100 1200 700]);
    drawWorldMapBackground();
    hold on;
    plot(dayData.longitude_deg, dayData.latitude_deg, "-", "Color", [0.05 0.20 0.55], "LineWidth", 0.9);
    scatter(dayData.longitude_deg, dayData.latitude_deg, 18, dayData.altitude_km, "filled");
    xlabel("Долгота");
    ylabel("Широта");
    title("Наземный трек учебного набора данных за " + string(targetDay, "yyyy-MM-dd"));
    cb = colorbar;
    cb.Label.String = "Высота, км";
    formatWorldMapAxes();
    exportgraphics(fig, fullfile(figureDir, "teaching_day_" + targetTag + "_ground_track.png"), "Resolution", 250);
    close(fig);
end

function plotDayMagneticNorm(dayData, dayTime, targetDay, figureDir, targetTag)
    fig = figure("Visible", "off", "Color", "w", "Position", [100 100 1200 620]);
    plot(dayTime, dayData.B_teaching_mGs, "Color", [0.05 0.25 0.65], "LineWidth", 0.9);
    hold on;
    anomalyMask = logical(dayData.is_anomaly) & isfinite(dayData.B_teaching_mGs);
    scatter(dayTime(anomalyMask), dayData.B_teaching_mGs(anomalyMask), 30, "r", "filled");
    xlabel("Время, UTC");
    ylabel("|B|, мГс");
    title("Модуль магнитного поля за " + string(targetDay, "yyyy-MM-dd"));
    legend("|B|", "Размеченные аномалии", "Location", "best");
    grid on;
    xlim([targetDay, targetDay + days(1)]);
    exportgraphics(fig, fullfile(figureDir, "teaching_day_" + targetTag + "_magnetic_norm.png"), "Resolution", 250);
    close(fig);
end

function plotDayGroundTrackMagneticNorm(dayData, targetDay, figureDir, targetTag)
    fig = figure("Visible", "off", "Color", "w", "Position", [100 100 1200 700]);
    drawWorldMapBackground();
    hold on;
    scatter(dayData.longitude_deg, dayData.latitude_deg, 22, dayData.B_teaching_mGs, "filled");
    xlabel("Долгота");
    ylabel("Широта");
    title("Наземный трек за " + string(targetDay, "yyyy-MM-dd") + ": цветом показан модуль магнитного поля");
    cb = colorbar;
    cb.Label.String = "|B|, мГс";
    formatWorldMapAxes();
    exportgraphics(fig, fullfile(figureDir, "teaching_day_" + targetTag + "_ground_track_magnetic_norm.png"), "Resolution", 250);
    close(fig);
end

function drawWorldMapBackground()
    try
        coast = load("coastlines");
        plot(coast.coastlon, coast.coastlat, "Color", [0.72 0.72 0.72], "LineWidth", 0.5);
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

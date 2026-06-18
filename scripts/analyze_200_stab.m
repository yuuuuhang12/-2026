%% Анализ данных Polytech-Universe: набор 200_stab
% Скрипт выполняет обработку данных магнитометра и навигации.
% Исходные файлы не изменяются.
%
% Входные файлы:
%   200_magn_stab.txt - время, Bx, By, Bz; время рассматривается как Unix time в мс.
%   200_lla_stab.csv  - RTC, RTC ms, высота, широта, долгота.
%
% В репозитории исходные файлы следует поместить в каталог:
%   data
%
% Основные выходные файлы сохраняются в каталогах:
%   results/figures
%   results/tables
%   results/summaries/analysis_summary_200_stab.txt

clear; clc; close all;

%% Определение рабочих каталогов
scriptDir = fileparts(mfilename('fullpath'));
repoDir = fileparts(scriptDir);
taskDir = fullfile(repoDir, 'data');
resultDir = fullfile(repoDir, 'results');
figDir = fullfile(resultDir, 'figures');
tableDir = fullfile(resultDir, 'tables');
summaryDir = fullfile(resultDir, 'summaries');

if ~exist(figDir, 'dir'); mkdir(figDir); end
if ~exist(tableDir, 'dir'); mkdir(tableDir); end
if ~exist(summaryDir, 'dir'); mkdir(summaryDir); end

magFile = fullfile(taskDir, '200_magn_stab.txt');
navFile = fullfile(taskDir, '200_lla_stab.csv');

% Для совместимости с исходной рабочей структурой выполняется резервный
% поиск файлов в каталоге "02 Work/01 Задание". В обычном Git-сценарии
% достаточно поместить исходные файлы в каталог data рядом с scripts.
if ~isfile(magFile) || ~isfile(navFile)
    legacyWorkDirs = {fullfile(scriptDir, '..', '..', '..'), fullfile(scriptDir, '..', '..')};
    for legacyIndex = 1:numel(legacyWorkDirs)
        legacyTaskDir = findNumberedSubdirIfExists(legacyWorkDirs{legacyIndex}, '01 ');
        if strlength(legacyTaskDir) > 0
            legacyMagFile = fullfile(legacyTaskDir, '200_magn_stab.txt');
            legacyNavFile = fullfile(legacyTaskDir, '200_lla_stab.csv');
            if isfile(legacyMagFile) && isfile(legacyNavFile)
                taskDir = legacyTaskDir;
                magFile = legacyMagFile;
                navFile = legacyNavFile;
                break;
            end
        end
    end
end

if ~isfile(magFile) || ~isfile(navFile)
    error(['Не найдены входные файлы 200_magn_stab.txt и 200_lla_stab.csv. ', ...
        'Поместите их в каталог data внутри репозитория.']);
end

fprintf('Чтение файла магнитометра: %s\n', magFile);
magRaw = readmatrix(magFile, 'FileType', 'text');

fprintf('Очистка данных магнитометра и восстановление отдельных временных меток...\n');
[mag, cleaningCounters, typicalStepMs] = cleanMagnetometerData(magRaw);

timeMs = mag(:, 1);
Bx = mag(:, 2);
By = mag(:, 3);
Bz = mag(:, 4);
Bnorm = sqrt(Bx.^2 + By.^2 + Bz.^2);
magTime = datetime(timeMs / 1000, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');

fprintf('Проверка единицы времени магнитометра...\n');
dtMs = diff(timeMs);
positiveDtMs = dtMs(dtMs > 0);
mostCommonDtMs = mode(positiveDtMs);
inferredTimeUnit = "мс";

fprintf('Расчет статистик магнитного поля и 3σ-проверок...\n');
axisStats = makeAxisStats(Bx, By, Bz);
BnormStats = makeNormStats(Bnorm);
spikeStats = makeDiffSpikeStats(timeMs, Bx, By, Bz, Bnorm);

fprintf('Чтение файла навигации: %s\n', navFile);
nav = readNavigationCsv(navFile);
navTimeMs = nav.timeMs;

fprintf('Сопоставление навигационных точек с данными магнитометра методом ближайшего соседа...\n');
[nearestMagIndex, syncErrorMs] = nearestNeighbor(timeMs, navTimeMs); %#ok<ASGLU>
syncStats = table( ...
    min(syncErrorMs), median(syncErrorMs), max(syncErrorMs), ...
    sum(syncErrorMs <= 10), sum(syncErrorMs <= 100), numel(syncErrorMs), ...
    'VariableNames', {'минимум_мс', 'медиана_мс', 'максимум_мс', ...
    'точек_до_10_мс', 'точек_до_100_мс', 'всего_навигационных_точек'});

fprintf('Оценка периода орбиты по положительным максимумам широты...\n');
[latPeakTimesMs, latPeakValues, orbitPeriodsMin] = estimateOrbitPeriod(navTimeMs, nav.latDeg);

fprintf('Запись таблиц статистики...\n');
cleaningStats = table( ...
    cleaningCounters.rawRows, ...
    cleaningCounters.invalidNumericRows, ...
    cleaningCounters.zeroTimeRows, ...
    cleaningCounters.zeroVectorRows, ...
    cleaningCounters.zeroTimeNonzeroVectorRows, ...
    cleaningCounters.recoveredTimeRows, ...
    cleaningCounters.unrecoveredTimeRows, ...
    cleaningCounters.analysisRows, ...
    height(nav), ...
    'VariableNames', {'исходные_строки', ...
    'строки_nan_или_нечисловые', ...
    'строки_с_нулевым_временем', ...
    'строки_с_нулевым_магнитным_вектором', ...
    'строки_с_нулевым_временем_и_ненулевым_вектором', ...
    'строки_с_восстановленным_временем', ...
    'строки_исключенные_из_за_невосстановленного_времени', ...
    'строки_для_анализа_магнитного_поля', ...
    'валидные_строки_навигации'});

timeStats = table( ...
    string(inferredTimeUnit), typicalStepMs, mostCommonDtMs, mostCommonDtMs / 1000, ...
    min(timeMs), max(timeMs), string(magTime(1)), string(magTime(end)), ...
    'VariableNames', {'единица_времени', 'типичный_шаг_мс', ...
    'наиболее_частый_шаг_мс', 'наиболее_частый_шаг_с', ...
    'первое_время_исходное', 'последнее_время_исходное', ...
    'первое_время_utc', 'последнее_время_utc'});

if numel(orbitPeriodsMin) > 0
    orbitStats = table( ...
        numel(latPeakTimesMs), mean(orbitPeriodsMin), min(orbitPeriodsMin), max(orbitPeriodsMin), ...
        'VariableNames', {'число_положительных_максимумов_широты', ...
        'средний_период_мин', 'минимальный_период_мин', 'максимальный_период_мин'});
else
    orbitStats = table(numel(latPeakTimesMs), NaN, NaN, NaN, ...
        'VariableNames', {'число_положительных_максимумов_широты', ...
        'средний_период_мин', 'минимальный_период_мин', 'максимальный_период_мин'});
end

writetable(cleaningStats, fullfile(tableDir, 'cleaning_stats_200_stab.csv'));
writetable(timeStats, fullfile(tableDir, 'time_stats_200_stab.csv'));
writetable(axisStats, fullfile(tableDir, 'axis_quality_200_stab.csv'));
writetable(BnormStats, fullfile(tableDir, 'magnetic_norm_stats_200_stab.csv'));
writetable(spikeStats, fullfile(tableDir, 'diff_spike_stats_200_stab.csv'));
writetable(syncStats, fullfile(tableDir, 'sync_stats_200_stab.csv'));
writetable(orbitStats, fullfile(tableDir, 'orbit_period_200_stab.csv'));

fprintf('Построение графиков для отчета...\n');
plotMagneticNorm(magTime, Bnorm, spikeStats, figDir);
plotSmoothedMagneticNorm(magTime, Bnorm, mostCommonDtMs, figDir);
plotGroundTrack(nav.lonDeg, nav.latDeg, nav.altM, figDir);

fprintf('Запись текстового резюме...\n');
summaryFile = fullfile(summaryDir, 'analysis_summary_200_stab.txt');
writeSummary(summaryFile, cleaningStats, timeStats, BnormStats, syncStats, orbitStats, ...
    latPeakTimesMs, latPeakValues);

fprintf('\nОбработка завершена.\n');
fprintf('Каталог графиков: %s\n', figDir);
fprintf('Каталог таблиц: %s\n', tableDir);
fprintf('Файл резюме: %s\n', summaryFile);

%% Локальные функции

function folderPath = findNumberedSubdir(parentDir, prefix)
    entries = dir(parentDir);
    isWanted = [entries.isdir] & startsWith({entries.name}, prefix);
    matches = entries(isWanted);

    if isempty(matches)
        error('Не найден подкаталог с префиксом "%s" в каталоге %s.', prefix, parentDir);
    end

    folderPath = fullfile(parentDir, matches(1).name);
end

function folderPath = findNumberedSubdirIfExists(parentDir, prefix)
    folderPath = "";
    if ~exist(parentDir, 'dir')
        return;
    end

    entries = dir(parentDir);
    isWanted = [entries.isdir] & startsWith({entries.name}, prefix);
    matches = entries(isWanted);

    if ~isempty(matches)
        folderPath = string(fullfile(parentDir, matches(1).name));
    end
end

function [magClean, counters, typicalStepMs] = cleanMagnetometerData(magRaw)
    % Очистка разделяет три случая:
    % 1) time == 0 и Bx == By == Bz == 0: полностью недействительная строка.
    % 2) time > 0 и Bx == By == Bz == 0: строка имеет время, но не имеет
    %    магнитного измерения; из анализа |B| исключается.
    % 3) time == 0 и магнитный вектор ненулевой: измерение может быть полезным.
    %    Время восстанавливается только при наличии соседних валидных временных
    %    меток и если строка укладывается в локальный разрыв с типичным шагом.

    counters.rawRows = size(magRaw, 1);
    counters.invalidNumericRows = sum(any(~isfinite(magRaw), 2));

    validNumeric = all(isfinite(magRaw), 2);
    t = magRaw(:, 1);
    b = magRaw(:, 2:4);

    zeroTime = validNumeric & t == 0;
    zeroVector = validNumeric & all(b == 0, 2);
    zeroTimeZeroVector = zeroTime & zeroVector;
    positiveTimeZeroVector = validNumeric & t > 0 & zeroVector;
    zeroTimeNonzeroVector = zeroTime & ~zeroVector;

    counters.zeroTimeRows = sum(zeroTime);
    counters.zeroVectorRows = sum(zeroVector);
    counters.zeroTimeNonzeroVectorRows = sum(zeroTimeNonzeroVector);

    normalMeasurement = validNumeric & t > 0 & ~zeroVector;
    validTimes = t(normalMeasurement);
    validDiffs = diff(sort(validTimes));
    validDiffs = validDiffs(validDiffs > 0 & validDiffs <= 100);

    if isempty(validDiffs)
        typicalStepMs = NaN;
        warning('Не удалось определить типичный шаг дискретизации; восстановление нулевых временных меток невозможно.');
    else
        typicalStepMs = mode(validDiffs);
    end

    restoredTime = t;
    recoveredMask = false(size(t));
    unrecoveredMask = false(size(t));
    candidateIdx = find(zeroTimeNonzeroVector);

    for k = 1:numel(candidateIdx)
        idx = candidateIdx(k);

        if isnan(typicalStepMs)
            unrecoveredMask(idx) = true;
            continue;
        end

        prevIdx = find(normalMeasurement(1:idx-1), 1, 'last');
        nextRelative = find(normalMeasurement(idx+1:end), 1, 'first');

        if isempty(prevIdx) || isempty(nextRelative)
            unrecoveredMask(idx) = true;
            continue;
        end

        nextIdx = idx + nextRelative;
        localZeroOrEmpty = all(zeroTime( prevIdx+1 : nextIdx-1 ) | positiveTimeZeroVector( prevIdx+1 : nextIdx-1 ));
        gapMs = t(nextIdx) - t(prevIdx);
        stepsInGap = round(gapMs / typicalStepMs);
        expectedInternalRows = stepsInGap - 1;
        internalRows = nextIdx - prevIdx - 1;

        if localZeroOrEmpty && gapMs > 0 && abs(gapMs - stepsInGap * typicalStepMs) < 1e-6 && ...
                expectedInternalRows == internalRows
            restoredTime(idx) = t(prevIdx) + (idx - prevIdx) * typicalStepMs;
            recoveredMask(idx) = true;
        else
            unrecoveredMask(idx) = true;
        end
    end

    counters.recoveredTimeRows = sum(recoveredMask);
    counters.unrecoveredTimeRows = sum(unrecoveredMask);

    analysisRows = normalMeasurement | recoveredMask;
    analysisRows = analysisRows & ~zeroTimeZeroVector & ~positiveTimeZeroVector & ~unrecoveredMask;
    counters.analysisRows = sum(analysisRows);

    magClean = [restoredTime(analysisRows), b(analysisRows, :)];
    magClean = sortrows(magClean, 1);
end

function nav = readNavigationCsv(navFile)
    lines = readlines(navFile, 'Encoding', 'UTF-8');
    lines = lines(2:end);

    timeText = strings(0, 1);
    rtcMs = [];
    altM = [];
    latDeg = [];
    lonDeg = [];

    for i = 1:numel(lines)
        line = strtrim(lines(i));
        if line == ""; continue; end

        parts = split(line, ';');
        if numel(parts) < 5; continue; end

        tText = strtrim(parts(1));
        if tText == ""; continue; end

        parsedRtc = str2double(strrep(parts(2), ',', '.'));
        parsedAlt = str2double(strrep(parts(3), ',', '.'));
        parsedLat = str2double(strrep(parts(4), ',', '.'));
        parsedLon = str2double(strrep(parts(5), ',', '.'));

        if any(isnan([parsedRtc, parsedAlt, parsedLat, parsedLon]))
            fprintf('Предупреждение: пропущена некорректная строка навигации: %s\n', line);
            continue;
        end

        timeText(end + 1, 1) = tText; %#ok<AGROW>
        rtcMs(end + 1, 1) = parsedRtc; %#ok<AGROW>
        altM(end + 1, 1) = parsedAlt; %#ok<AGROW>
        latDeg(end + 1, 1) = parsedLat; %#ok<AGROW>
        lonDeg(end + 1, 1) = parsedLon; %#ok<AGROW>
    end

    navDateTime = datetime(timeText, 'InputFormat', 'dd-MM-yyyy HH:mm:ss:SSS', 'TimeZone', 'UTC');
    timeMs = posixtime(navDateTime) * 1000;

    nav = table(timeText, timeMs, rtcMs, altM, latDeg, lonDeg, ...
        'VariableNames', {'исходное_время', 'timeMs', 'rtcMsColumn', 'altM', 'latDeg', 'lonDeg'});
end

function stats = makeAxisStats(Bx, By, Bz)
    labels = ["Bx"; "By"; "Bz"];
    values = {Bx; By; Bz};
    meanValue = zeros(3, 1);
    stdValue = zeros(3, 1);
    minValue = zeros(3, 1);
    maxValue = zeros(3, 1);
    zeroCount = zeros(3, 1);
    outlierCount = zeros(3, 1);

    for i = 1:3
        v = values{i};
        meanValue(i) = mean(v);
        stdValue(i) = std(v, 1);
        minValue(i) = min(v);
        maxValue(i) = max(v);
        zeroCount(i) = sum(v == 0);
        lo = meanValue(i) - 3 * stdValue(i);
        hi = meanValue(i) + 3 * stdValue(i);
        outlierCount(i) = sum(v < lo | v > hi);
    end

    stats = table(labels, meanValue, stdValue, minValue, maxValue, zeroCount, outlierCount, ...
        'VariableNames', {'ось', 'среднее', 'стандартное_отклонение', ...
        'минимум', 'максимум', 'нулевые_значения', 'выбросы_3сигма'});
end

function stats = makeNormStats(Bnorm)
    meanValue = mean(Bnorm);
    stdValue = std(Bnorm, 1);
    minValue = min(Bnorm);
    maxValue = max(Bnorm);
    lo = meanValue - 3 * stdValue;
    hi = meanValue + 3 * stdValue;
    outlierCount = sum(Bnorm < lo | Bnorm > hi);

    stats = table(meanValue, stdValue, minValue, maxValue, lo, hi, outlierCount, ...
        'VariableNames', {'среднее', 'стандартное_отклонение', 'минимум', ...
        'максимум', 'нижняя_граница_3сигма', 'верхняя_граница_3сигма', ...
        'выбросы_3сигма'});
end

function stats = makeDiffSpikeStats(timeMs, Bx, By, Bz, Bnorm)
    labels = ["Bx"; "By"; "Bz"; "|B|"];
    values = {Bx; By; Bz; Bnorm};
    diffMean = zeros(4, 1);
    diffStd = zeros(4, 1);
    low = zeros(4, 1);
    high = zeros(4, 1);
    spikeCount = zeros(4, 1);
    maxAbsDiff = zeros(4, 1);

    validStep = diff(timeMs) > 0 & diff(timeMs) <= 100;

    for i = 1:4
        d = diff(values{i});
        d = d(validStep);
        diffMean(i) = mean(d);
        diffStd(i) = std(d, 1);
        low(i) = diffMean(i) - 3 * diffStd(i);
        high(i) = diffMean(i) + 3 * diffStd(i);
        spikeCount(i) = sum(d < low(i) | d > high(i));
        maxAbsDiff(i) = max(abs(d));
    end

    stats = table(labels, diffMean, diffStd, low, high, spikeCount, maxAbsDiff, ...
        'VariableNames', {'сигнал', 'среднее_разности', 'стандартное_отклонение_разности', ...
        'нижняя_граница_3сигма', 'верхняя_граница_3сигма', ...
        'число_скачков', 'максимальная_абсолютная_разность'});
end

function [indices, errorsMs] = nearestNeighbor(referenceTimesMs, queryTimesMs)
    indices = zeros(numel(queryTimesMs), 1);
    errorsMs = zeros(numel(queryTimesMs), 1);

    for i = 1:numel(queryTimesMs)
        q = queryTimesMs(i);
        right = find(referenceTimesMs >= q, 1, 'first');

        if isempty(right)
            idx = numel(referenceTimesMs);
        elseif right == 1
            idx = 1;
        else
            left = right - 1;
            if abs(referenceTimesMs(left) - q) <= abs(referenceTimesMs(right) - q)
                idx = left;
            else
                idx = right;
            end
        end

        indices(i) = idx;
        errorsMs(i) = abs(referenceTimesMs(idx) - q);
    end
end

function [peakTimesMs, peakValues, periodsMin] = estimateOrbitPeriod(timeMs, latDeg)
    peakTimesMs = [];
    peakValues = [];

    for i = 2:numel(latDeg)-1
        if latDeg(i) > latDeg(i - 1) && latDeg(i) >= latDeg(i + 1) && latDeg(i) > 70
            peakTimesMs(end + 1, 1) = timeMs(i); %#ok<AGROW>
            peakValues(end + 1, 1) = latDeg(i); %#ok<AGROW>
        end
    end

    periodsMin = diff(peakTimesMs) / 1000 / 60;
end

function plotMagneticNorm(magTime, Bnorm, spikeStats, figDir)
    fig = figure('Color', 'w', 'Position', [100 100 1200 520]);
    plot(magTime, Bnorm, 'Color', [0.05 0.25 0.55], 'LineWidth', 0.8);
    grid on;

    xlabel('Время, UTC');
    ylabel('|B|, мГс');
    title('Модуль магнитного поля, 200\_magn\_stab');
    spikeLabels = spikeStats{:, 'сигнал'};
    normSpikeCount = spikeStats{spikeLabels == "|B|", 'число_скачков'};
    subtitleText = sprintf('Среднее %.2f мГс, СКО %.2f мГс; скачки |B| по 3σ: %d', ...
        mean(Bnorm), std(Bnorm, 1), normSpikeCount);
    subtitle(subtitleText);
    legend({'|B|'}, 'Location', 'best');

    exportgraphics(fig, fullfile(figDir, 'magnetic_field_norm_200_stab.png'), 'Resolution', 300);
    savefig(fig, fullfile(figDir, 'magnetic_field_norm_200_stab.fig'));
end

function plotSmoothedMagneticNorm(magTime, Bnorm, mostCommonDtMs, figDir)
    % Сглаженная кривая используется только для визуального наблюдения общей
    % тенденции. Она не применяется для расчета статистик исходных данных.
    if isnan(mostCommonDtMs) || mostCommonDtMs <= 0
        windowPoints = 1000;
        fprintf('Предупреждение: шаг дискретизации не определен; для сглаживания используется окно 1000 точек.\n');
    else
        windowSeconds = 30;
        windowPoints = max(3, round(windowSeconds * 1000 / mostCommonDtMs));
    end

    Bsmooth = movmedian(Bnorm, windowPoints, 'omitnan');

    fig = figure('Color', 'w', 'Position', [120 120 1200 520]);
    plot(magTime, Bnorm, 'Color', [0.75 0.78 0.82], 'LineWidth', 0.4);
    hold on; grid on;
    plot(magTime, Bsmooth, 'Color', [0.10 0.35 0.15], 'LineWidth', 1.4);

    xlabel('Время, UTC');
    ylabel('|B|, мГс');
    title('Сглаженный тренд модуля магнитного поля, 200\_magn\_stab');
    subtitle(sprintf('Скользящая медиана, окно %d точек; график используется только для оценки тенденции', windowPoints));
    legend({'Исходный |B|', 'Сглаженный тренд'}, 'Location', 'best');

    exportgraphics(fig, fullfile(figDir, 'magnetic_field_norm_smoothed_200_stab.png'), 'Resolution', 300);
end

function plotGroundTrack(lonDeg, latDeg, altM, figDir)
    fig = figure('Color', 'w', 'Position', [120 120 1100 620]);
    usedMapBackground = false;

    if exist('geoscatter', 'file') == 2 && exist('geobasemap', 'file') == 2
        try
            geoscatter(latDeg, lonDeg, 28, altM / 1000, 'filled');
            geobasemap('grayland');
            title('Наземный трек спутника с цветовым отображением высоты, 200\_lla\_stab');
            cb = colorbar;
            cb.Label.String = 'Высота, км';
            colormap(turbo);
            hold on;
            geoscatter(latDeg(1), lonDeg(1), 55, 'g', 'filled');
            geoscatter(latDeg(end), lonDeg(end), 55, 'r', 'filled');
            legend({'Точки трека', 'Начало', 'Конец'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
            usedMapBackground = true;
            fprintf('Наземный трек построен на картографической подложке MATLAB.\n');
        catch ME
            fprintf('Картографическая подложка недоступна: %s\n', ME.message);
            fprintf('Будет построен обычный график долгота-широта.\n');
            clf(fig);
        end
    else
        fprintf('Картографические функции MATLAB недоступны. Будет построен обычный график долгота-широта.\n');
    end

    if ~usedMapBackground
        scatter(lonDeg, latDeg, 28, altM / 1000, 'filled');
        grid on;
        xlim([-180 180]);
        ylim([-90 90]);
        xlabel('Долгота, град');
        ylabel('Широта, град');
        title('Наземный трек спутника с цветовым отображением высоты, 200\_lla\_stab');
        cb = colorbar;
        cb.Label.String = 'Высота, км';
        colormap(turbo);
        hold on;
        plot(lonDeg(1), latDeg(1), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 7);
        plot(lonDeg(end), latDeg(end), 'rs', 'MarkerFaceColor', 'r', 'MarkerSize', 7);
        legend({'Точки трека', 'Начало', 'Конец'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
    end

    exportgraphics(fig, fullfile(figDir, 'ground_track_altitude_200_stab.png'), 'Resolution', 300);
    savefig(fig, fullfile(figDir, 'ground_track_altitude_200_stab.fig'));
end

function writeSummary(summaryFile, cleaningStats, timeStats, BnormStats, syncStats, orbitStats, latPeakTimesMs, latPeakValues)
    fid = fopen(summaryFile, 'w', 'n', 'UTF-8');
    if fid < 0
        error('Не удалось открыть файл резюме для записи: %s', summaryFile);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'Сводка анализа данных Polytech-Universe, набор 200_stab\n');
    fprintf(fid, '=====================================================\n\n');

    fprintf(fid, 'Очистка данных\n');
    fprintf(fid, '- Исходные строки магнитометра: %d\n', tableValue(cleaningStats, 'исходные_строки'));
    fprintf(fid, '- Строки с NaN или нечисловыми значениями: %d\n', tableValue(cleaningStats, 'строки_nan_или_нечисловые'));
    fprintf(fid, '- Строки с нулевым временем: %d\n', tableValue(cleaningStats, 'строки_с_нулевым_временем'));
    fprintf(fid, '- Строки с нулевым магнитным вектором: %d\n', tableValue(cleaningStats, 'строки_с_нулевым_магнитным_вектором'));
    fprintf(fid, '- Строки с нулевым временем и ненулевым вектором: %d\n', tableValue(cleaningStats, 'строки_с_нулевым_временем_и_ненулевым_вектором'));
    fprintf(fid, '- Строки с восстановленным временем: %d\n', tableValue(cleaningStats, 'строки_с_восстановленным_временем'));
    fprintf(fid, '- Строки, исключенные из-за невосстановленного времени: %d\n', tableValue(cleaningStats, 'строки_исключенные_из_за_невосстановленного_времени'));
    fprintf(fid, '- Строки для анализа магнитного поля: %d\n', tableValue(cleaningStats, 'строки_для_анализа_магнитного_поля'));
    fprintf(fid, '- Валидные строки навигации: %d\n\n', tableValue(cleaningStats, 'валидные_строки_навигации'));

    fprintf(fid, 'Временная шкала\n');
    fprintf(fid, '- Единица времени магнитометра: %s\n', string(tableValue(timeStats, 'единица_времени')));
    fprintf(fid, '- Типичный шаг дискретизации: %.3f мс\n', tableValue(timeStats, 'типичный_шаг_мс'));
    fprintf(fid, '- Наиболее частый шаг дискретизации: %.3f мс\n', tableValue(timeStats, 'наиболее_частый_шаг_мс'));
    fprintf(fid, '- Интервал UTC: %s - %s\n\n', string(tableValue(timeStats, 'первое_время_utc')), string(tableValue(timeStats, 'последнее_время_utc')));

    fprintf(fid, 'Модуль магнитного поля |B|\n');
    fprintf(fid, '- Среднее: %.6f мГс\n', tableValue(BnormStats, 'среднее'));
    fprintf(fid, '- Стандартное отклонение: %.6f мГс\n', tableValue(BnormStats, 'стандартное_отклонение'));
    fprintf(fid, '- Минимум: %.6f мГс\n', tableValue(BnormStats, 'минимум'));
    fprintf(fid, '- Максимум: %.6f мГс\n\n', tableValue(BnormStats, 'максимум'));

    fprintf(fid, 'Синхронизация навигации и магнитометра\n');
    fprintf(fid, '- Ошибка ближайшего соседа min/median/max: %.3f / %.3f / %.3f мс\n', ...
        tableValue(syncStats, 'минимум_мс'), tableValue(syncStats, 'медиана_мс'), tableValue(syncStats, 'максимум_мс'));
    fprintf(fid, '- Точек с ошибкой не более 10 мс: %d из %d\n', ...
        tableValue(syncStats, 'точек_до_10_мс'), tableValue(syncStats, 'всего_навигационных_точек'));
    fprintf(fid, '- Точек с ошибкой не более 100 мс: %d из %d\n\n', ...
        tableValue(syncStats, 'точек_до_100_мс'), tableValue(syncStats, 'всего_навигационных_точек'));

    fprintf(fid, 'Оценка периода орбиты\n');
    if ~isnan(tableValue(orbitStats, 'средний_период_мин'))
        fprintf(fid, '- Число положительных максимумов широты: %d\n', tableValue(orbitStats, 'число_положительных_максимумов_широты'));
        for i = 1:numel(latPeakTimesMs)
            t = datetime(latPeakTimesMs(i) / 1000, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
            fprintf(fid, '  - %s, широта %.6f град\n', string(t), latPeakValues(i));
        end
        fprintf(fid, '- Оцененный период: %.3f мин\n\n', tableValue(orbitStats, 'средний_период_мин'));
    else
        fprintf(fid, '- Недостаточно положительных максимумов широты для оценки периода.\n\n');
    end

    fprintf(fid, 'Примечания для отчета\n');
    fprintf(fid, '- Высота отображается цветом на графике наземного трека, отдельный график высоты от времени не формируется.\n');
    fprintf(fid, '- Скачки по разности 3σ учитываются статистически, но автоматически не удаляются.\n');
    fprintf(fid, '- Сглаженный график |B| используется только для визуальной оценки тренда и не влияет на статистику.\n');
end

function value = tableValue(tbl, variableName)
    value = tbl{1, variableName};
end

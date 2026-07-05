%% Наземный трек с цветовым отображением модуля магнитного поля
% Русское название: Построение наземного трека по модулю магнитного поля.
% Скрипт сопоставляет каждую навигационную точку с ближайшим по времени
% магнитометрическим измерением и строит трек, где цвет точки показывает |B|.
% Используется ближайший сосед, потому что навигационная запись дискретна.

clear; clc; close all;

scriptDir = fileparts(mfilename('fullpath'));
scriptsRootDir = fileparts(scriptDir);
repoDir = fileparts(scriptsRootDir);
commonScriptDir = fullfile(scriptsRootDir, '03_общие_функции');
if exist(commonScriptDir, 'dir'); addpath(commonScriptDir); end

outputRootDir = fullfile(repoDir, 'Задание 1 · Анализ данных');
figDir = fullfile(outputRootDir, 'figures');
tableDir = fullfile(outputRootDir, 'tables');

if ~exist(figDir, 'dir'); mkdir(figDir); end
if ~exist(tableDir, 'dir'); mkdir(tableDir); end

datasets = struct( ...
    'suffix', {'200_stab', '201_ori'}, ...
    'titleSuffix', {'200\_stab', '201\_ori'}, ...
    'magName', {'200_magn_stab.txt', '201_magn_ori.txt'}, ...
    'navName', {'200_lla_stab.csv', '201_lla_ori.csv'});

%% Обработка обоих исходных наборов
% Для 200_stab и 201_ori формируется отдельная таблица синхронизированных
% навигационных точек и отдельный график наземного трека.
for datasetIndex = 1:numel(datasets)
    processDataset(datasets(datasetIndex), repoDir, figDir, tableDir);
end

fprintf('\nDone.\n');
fprintf('Figures: %s\n', figDir);
fprintf('Tables:  %s\n', tableDir);

function processDataset(dataset, repoDir, figDir, tableDir)
    [magFile, navFile] = resolveInputFiles(repoDir, dataset.magName, dataset.navName);

    fprintf('\nDataset %s\n', dataset.suffix);
    fprintf('Reading magnetometer file: %s\n', magFile);
    magRaw = readmatrix(magFile, 'FileType', 'text');
    mag = cleanMagnetometerData(magRaw);

    magTimeMs = mag(:, 1);
    Bx = mag(:, 2);
    By = mag(:, 3);
    Bz = mag(:, 4);
    Bnorm = sqrt(Bx.^2 + By.^2 + Bz.^2);
    magDateTime = datetime(magTimeMs / 1000, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');

    fprintf('Reading navigation file: %s\n', navFile);
    nav = readNavigationCsv(navFile);
    navTimeMs = nav.timeMs;
    navDateTime = datetime(navTimeMs / 1000, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');

    [nearestMagIndex, syncErrorMs] = nearestNeighbor(magTimeMs, navTimeMs);
    matchedTimeMs = magTimeMs(nearestMagIndex);
    matchedDateTime = magDateTime(nearestMagIndex);
    matchedBx = Bx(nearestMagIndex);
    matchedBy = By(nearestMagIndex);
    matchedBz = Bz(nearestMagIndex);
    matchedBnorm = Bnorm(nearestMagIndex);

    outTable = table( ...
        string(nav.timeText), ...
        navDateTime, ...
        nav.latDeg, ...
        nav.lonDeg, ...
        nav.altM, ...
        matchedTimeMs, ...
        matchedDateTime, ...
        matchedBx, ...
        matchedBy, ...
        matchedBz, ...
        matchedBnorm, ...
        syncErrorMs, ...
        'VariableNames', {'navTimeText', 'navTimeUtc', 'latDeg', 'lonDeg', 'altM', ...
        'matchedMagTimeMs', 'matchedMagTimeUtc', 'Bx_mGs', 'By_mGs', 'Bz_mGs', ...
        'Bnorm_mGs', 'syncErrorMs'});

    tablePath = fullfile(tableDir, ['ground_track_magnetic_norm_', dataset.suffix, '.csv']);
    writetable(outTable, tablePath);

    plotGroundTrackMagneticNorm(nav.lonDeg, nav.latDeg, matchedBnorm, syncErrorMs, ...
        dataset.suffix, dataset.titleSuffix, figDir);

    fprintf('Navigation points: %d\n', height(nav));
    fprintf('Sync error, ms: min %.0f, median %.0f, max %.0f; <=10 ms: %d/%d; <=100 ms: %d/%d\n', ...
        min(syncErrorMs), median(syncErrorMs), max(syncErrorMs), ...
        sum(syncErrorMs <= 10), numel(syncErrorMs), ...
        sum(syncErrorMs <= 100), numel(syncErrorMs));
    fprintf('Wrote table: %s\n', tablePath);
end

function [magFile, navFile] = resolveInputFiles(repoDir, magName, navName)
    dataDir = fullfile(repoDir, 'Исходные данные');
    magFile = fullfile(dataDir, magName);
    navFile = fullfile(dataDir, navName);

    if isfile(magFile) && isfile(navFile)
        return;
    end

    legacyWorkDirs = {fullfile(repoDir, '..', '..'), fullfile(repoDir, '..')};
    for i = 1:numel(legacyWorkDirs)
        taskDir = findNumberedSubdirIfExists(legacyWorkDirs{i}, '01 ');
        if strlength(taskDir) == 0
            continue;
        end

        candidateMagFile = fullfile(taskDir, magName);
        candidateNavFile = fullfile(taskDir, navName);
        if isfile(candidateMagFile) && isfile(candidateNavFile)
            magFile = candidateMagFile;
            navFile = candidateNavFile;
            return;
        end
    end

    error('Input files not found: %s and %s.', magName, navName);
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

function magClean = cleanMagnetometerData(magRaw)
    validNumeric = all(isfinite(magRaw), 2);
    t = magRaw(:, 1);
    b = magRaw(:, 2:4);

    zeroTime = validNumeric & t == 0;
    zeroVector = validNumeric & all(b == 0, 2);
    zeroTimeZeroVector = zeroTime & zeroVector;
    positiveTimeZeroVector = validNumeric & t > 0 & zeroVector;
    zeroTimeNonzeroVector = zeroTime & ~zeroVector;

    normalMeasurement = validNumeric & t > 0 & ~zeroVector;
    validTimes = t(normalMeasurement);
    validDiffs = diff(sort(validTimes));
    validDiffs = validDiffs(validDiffs > 0 & validDiffs <= 100);

    if isempty(validDiffs)
        typicalStepMs = NaN;
        warning('Could not infer typical magnetometer sampling step; zero timestamps will not be restored.');
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
        localZeroOrEmpty = all(zeroTime(prevIdx+1:nextIdx-1) | positiveTimeZeroVector(prevIdx+1:nextIdx-1));
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

    analysisRows = normalMeasurement | recoveredMask;
    analysisRows = analysisRows & ~zeroTimeZeroVector & ~positiveTimeZeroVector & ~unrecoveredMask;
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

        parsedRtc = str2double(strrep(parts(2), ',', '.'));
        parsedAlt = str2double(strrep(parts(3), ',', '.'));
        parsedLat = str2double(strrep(parts(4), ',', '.'));
        parsedLon = str2double(strrep(parts(5), ',', '.'));

        if any(isnan([parsedRtc, parsedAlt, parsedLat, parsedLon]))
            warning('Skipping invalid navigation row: %s', line);
            continue;
        end

        timeText(end + 1, 1) = strtrim(parts(1)); %#ok<AGROW>
        rtcMs(end + 1, 1) = parsedRtc; %#ok<AGROW>
        altM(end + 1, 1) = parsedAlt; %#ok<AGROW>
        latDeg(end + 1, 1) = parsedLat; %#ok<AGROW>
        lonDeg(end + 1, 1) = parsedLon; %#ok<AGROW>
    end

    navDateTime = datetime(timeText, 'InputFormat', 'dd-MM-yyyy HH:mm:ss:SSS', 'TimeZone', 'UTC');
    timeMs = posixtime(navDateTime) * 1000;

    nav = table(timeText, timeMs, rtcMs, altM, latDeg, lonDeg, ...
        'VariableNames', {'timeText', 'timeMs', 'rtcMsColumn', 'altM', 'latDeg', 'lonDeg'});
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

function plotGroundTrackMagneticNorm(lonDeg, latDeg, Bnorm, syncErrorMs, datasetSuffix, titleSuffix, figDir)
    subtitleText = sprintf('Синхронизация ближайшим соседом; медианная ошибка %.0f мс, максимум %.0f мс', ...
        median(syncErrorMs), max(syncErrorMs));
    fig = plotUnifiedGroundTrackMap(lonDeg, latDeg, Bnorm, ...
        ['Наземный трек с цветовым отображением |B|, ', titleSuffix], ...
        '|B|, мГс', 'Subtitle', subtitleText);

    pngPath = fullfile(figDir, ['ground_track_magnetic_norm_', datasetSuffix, '.png']);
    figPath = fullfile(figDir, ['ground_track_magnetic_norm_', datasetSuffix, '.fig']);
    exportgraphics(fig, pngPath, 'Resolution', 300);
    savefig(fig, figPath);
    fprintf('Wrote figure: %s\n', pngPath);
end

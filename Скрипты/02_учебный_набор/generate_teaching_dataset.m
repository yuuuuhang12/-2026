
%% Генератор полусинтетического учебного набора спутниковых магнитных данных
% Русское название: Генерация учебного полусинтетического набора данных.
% Скрипт создает компактный учебный набор:
% орбитальное положение -> теоретическое поле IGRF -> реальный остаток ->
% контролируемые учебные аномалии.
%
% Входные файлы сначала ищутся в "Исходные данные/", затем в исходной рабочей папке
% 02 Work/01 Задание для совместимости со старой структурой.
%
% Выходные файлы:
%   Задание 2 · Данные для обучения/data/teaching_satellite_dataset.csv
%   Задание 2 · Данные для обучения/data/anomaly_description.csv
%   Задание 2 · Данные для обучения/data/metadata.json
%   Задание 2 · Данные для обучения/raw_like/teaching_magn_semisynth.txt
%   Задание 2 · Данные для обучения/raw_like/teaching_lla_semisynth.csv
%   Задание 2 · Данные для обучения/analysis_figures/*.png

clear; clc; close all;
scriptDir = fileparts(mfilename("fullpath"));
scriptsRootDir = fileparts(scriptDir);
repoDir = fileparts(scriptsRootDir);
commonScriptDir = fullfile(scriptsRootDir, "03_общие_функции");
if exist(commonScriptDir, "dir"); addpath(commonScriptDir); end

config = defaultTeachingGeneratorConfig();
rng(config.randomSeed, "twister");

%% Подготовка каталогов и входных файлов
% Определяется корень репозитория, создаются выходные папки и находятся
% исходные файлы магнитометра и навигации.
outputDir = fullfile(repoDir, config.output.rootDirName);
outputDataDir = fullfile(outputDir, "data");
outputRawLikeDir = fullfile(outputDir, "raw_like");
outputFigureDir = fullfile(outputDir, "analysis_figures");

if ~exist(outputDataDir, "dir"); mkdir(outputDataDir); end
if ~exist(outputRawLikeDir, "dir"); mkdir(outputRawLikeDir); end
if ~exist(outputFigureDir, "dir"); mkdir(outputFigureDir); end

magFile = findInputFile(repoDir, config.input.magFileName);
navFile = findInputFile(repoDir, config.input.navFileName);

fprintf("Reading source magnetometer file: %s\n", magFile);
magRaw = readmatrix(magFile, "FileType", "text");
mag = cleanMagnetometerForTeaching(magRaw);
magTimeMs = mag(:, 1);
BnormRealMGs = sqrt(sum(mag(:, 2:4).^2, 2));

fprintf("Reading source navigation file: %s\n", navFile);
nav = readNavigationCsv(navFile);

%% Привязка реальных магнитных измерений к навигации
% Для каждой навигационной точки берется ближайшее магнитометрическое
% измерение; разность с моделью IGRF затем используется как реальный остаток.
fprintf("Synchronizing navigation points with real magnetometer data...\n");
[nearestIndex, syncErrorMs] = nearestNeighbor(magTimeMs, nav.timeMs);
nav.BnormRealMGs = BnormRealMGs(nearestIndex);
nav.syncErrorMs = syncErrorMs;

fprintf("Calculating IGRF-14 theoretical magnetic field for source data...\n");
[~, sourceFModelNT] = calculateIgrf(nav.timeUtc, nav.altitudeM, nav.latitudeDeg, nav.longitudeDeg);
sourceFModelMGs = sourceFModelNT * 0.01;
sourceResidualMGs = nav.BnormRealMGs - sourceFModelMGs;

normalResidualMGs = selectNormalResiduals(sourceResidualMGs, config.residual);
if numel(normalResidualMGs) < 100
    error("Too few normal residual samples after filtering.");
end

fprintf("Building six-month educational time blocks...\n");
teaching = buildTeachingTimeline(nav, normalResidualMGs, config);

%% Построение учебной шкалы и расчет модели IGRF
% Реальные фрагменты переносятся в учебные интервалы, после чего для
% каждой точки рассчитывается теоретическое магнитное поле.
fprintf("Calculating IGRF-14 theoretical magnetic field for teaching timeline...\n");
[modelXYZnT, modelFNT] = calculateIgrf(teaching.timestampUtc, ...
    teaching.altitudeKm * 1000, teaching.latitudeDeg, teaching.longitudeDeg);

teaching.BxModelNT = modelXYZnT(:, 1);
teaching.ByModelNT = modelXYZnT(:, 2);
teaching.BzModelNT = modelXYZnT(:, 3);
teaching.BModelNT = modelFNT;
teaching.BModelMGs = modelFNT * 0.01;
teaching.BTeachingMGs = teaching.BModelMGs + teaching.residualMGs;
teaching.isAnomaly = false(height(teaching), 1);
teaching.anomalyType = repmat("normal", height(teaching), 1);
teaching.anomalyId = repmat("", height(teaching), 1);
teaching.qualityFlag = repmat("normal_semisynthetic", height(teaching), 1);

fprintf("Injecting controlled teaching anomalies...\n");
[teaching, anomalies] = injectTeachingAnomalies(teaching, config);
teaching = addTeachingVectorComponents(teaching);

%% Экспорт учебного набора и контрольных материалов
% Записываются основной CSV, описание аномалий, raw-like файлы, metadata,
% metadata и проверочные графики для отчета.
fprintf("Writing CSV, metadata and validation figures...\n");
teachingOutput = makeTeachingOutputTable(teaching);
writetable(teachingOutput, fullfile(outputDataDir, "teaching_satellite_dataset.csv"));
writetable(anomalies, fullfile(outputDataDir, "anomaly_description.csv"));
writeRawLikeFiles(teaching, outputRawLikeDir);
writeMetadata(outputDataDir, height(teaching), height(anomalies), magFile, navFile, config);
plotTeachingDataset(teaching, outputFigureDir);

fprintf("\nTeaching dataset generation completed.\n");
fprintf("Dataset: %s\n", fullfile(outputDataDir, "teaching_satellite_dataset.csv"));
fprintf("Raw-like magnetometer file: %s\n", fullfile(outputRawLikeDir, "teaching_magn_semisynth.txt"));
fprintf("Raw-like navigation file: %s\n", fullfile(outputRawLikeDir, "teaching_lla_semisynth.csv"));
fprintf("Anomaly description: %s\n", fullfile(outputDataDir, "anomaly_description.csv"));
fprintf("Figures: %s\n", outputFigureDir);

%% Local functions
% Вспомогательные функции расположены в конце файла, чтобы основной сценарий
% оставался компактным и читался сверху вниз как технологический процесс.

function filePath = findInputFile(repoDir, fileName)
    % Поиск входного файла сделан с несколькими вариантами пути: это позволяет
    % запускать скрипт как из репозитория, так и рядом с исходной папкой задания.
    candidates = [
        fullfile(repoDir, "Исходные данные", fileName)
        fullfile(repoDir, "..", "..", "01 Задание", fileName)
        fullfile(repoDir, "..", "01 Задание", fileName)
        ];

    for i = 1:numel(candidates)
        candidate = char(candidates(i));
        if isfile(candidate)
            filePath = candidate;
            return;
        end
    end

    error("Input file not found: %s. Put it in repository folder Исходные данные/.", fileName);
end

function mag = cleanMagnetometerForTeaching(magRaw)
    % Предварительная очистка магнитометрии: удаляются строки с NaN/Inf,
    % нулевым временем, нулевым магнитным вектором и повторяющимися метками.
    validNumeric = all(isfinite(magRaw), 2);
    mag = magRaw(validNumeric, :);
    hasPositiveTime = mag(:, 1) > 0;
    hasNonzeroVector = any(mag(:, 2:4) ~= 0, 2);
    mag = mag(hasPositiveTime & hasNonzeroVector, :);
    [~, uniqueIndex] = unique(mag(:, 1), "stable");
    mag = mag(uniqueIndex, :);
    mag = sortrows(mag, 1);
end

function nav = readNavigationCsv(navFile)
    % Чтение навигационного CSV вручную нужно из-за специфического формата:
    % разделитель ';', десятичная запятая и временная метка вида dd-MM-yyyy.
    rawLines = readlines(navFile);
    rawLines = rawLines(strlength(strtrim(rawLines)) > 0);
    dataLines = rawLines(2:end);

    timeUtc = NaT(0, 1, "TimeZone", "UTC");
    altitudeM = [];
    latitudeDeg = [];
    longitudeDeg = [];

    for i = 1:numel(dataLines)
        parts = split(dataLines(i), ";");
        if numel(parts) < 5
            continue;
        end

        timeText = strtrim(parts(1));
        altText = strtrim(parts(3));
        latText = strtrim(parts(4));
        lonText = strtrim(parts(5));

        try
            currentTime = datetime(timeText, "InputFormat", "dd-MM-yyyy HH:mm:ss:SSS", "TimeZone", "UTC");
        catch
            continue;
        end

        % Замена десятичной запятой на точку делает чтение устойчивым
        % к русско-европейскому формату чисел.
        parsedAlt = str2double(strrep(altText, ",", "."));
        parsedLat = str2double(strrep(latText, ",", "."));
        parsedLon = str2double(strrep(lonText, ",", "."));

        if any(~isfinite([parsedAlt, parsedLat, parsedLon]))
            continue;
        end

        timeUtc(end + 1, 1) = currentTime; %#ok<AGROW>
        altitudeM(end + 1, 1) = parsedAlt; %#ok<AGROW>
        latitudeDeg(end + 1, 1) = parsedLat; %#ok<AGROW>
        longitudeDeg(end + 1, 1) = parsedLon; %#ok<AGROW>
    end

    timeMs = posixtime(timeUtc) * 1000;
    nav = table(timeUtc, timeMs, altitudeM, latitudeDeg, longitudeDeg);
end

function [nearestIndex, syncErrorMs] = nearestNeighbor(sourceTimeMs, queryTimeMs)
    % Синхронизация выполняется по принципу ближайшего соседа: для каждой
    % навигационной точки выбирается ближайшее по времени измерение магнитометра.
    nearestIndex = zeros(size(queryTimeMs));
    syncErrorMs = zeros(size(queryTimeMs));

    for i = 1:numel(queryTimeMs)
        [syncErrorMs(i), nearestIndex(i)] = min(abs(sourceTimeMs - queryTimeMs(i)));
    end
end

function [XYZnT, FNT] = calculateIgrf(timeUtc, altitudeM, latitudeDeg, longitudeDeg)
    % Расчет теоретического поля по IGRF-14. На этом этапе важно контролировать
    % единицы высоты в соответствии с используемой версией функции igrfmagm.
    decimalYear = decimalYearFromDatetime(timeUtc);
    [XYZnT, ~, ~, ~, FNT] = igrfmagm(altitudeM, latitudeDeg, longitudeDeg, decimalYear, 14);
end

function decimalYear = decimalYearFromDatetime(timeUtc)
    % IGRF использует десятичный год, поэтому дата переводится из datetime
    % в формат вида 2026.35 с учетом положения внутри календарного года.
    years = year(timeUtc);
    startOfYear = datetime(years, 1, 1, 0, 0, 0, "TimeZone", "UTC");
    startNextYear = datetime(years + 1, 1, 1, 0, 0, 0, "TimeZone", "UTC");
    decimalYear = years + seconds(timeUtc - startOfYear) ./ seconds(startNextYear - startOfYear);
end

function residual = selectNormalResiduals(sourceResidualMGs, residualConfig)
    % Отбор "нормальных" остатков выполняется робастно через медиану и MAD,
    % чтобы сильные выбросы исходных данных не попали в обычный шумовой фон.
    finiteResidual = sourceResidualMGs(isfinite(sourceResidualMGs));
    medianValue = median(finiteResidual);
    madValue = median(abs(finiteResidual - medianValue));
    if madValue <= 0 || ~isfinite(madValue)
        % Резервный вариант используется, если MAD неинформативен: в этом
        % случае берется центральная часть распределения по процентилям.
        lo = prctile(finiteResidual, 2);
        hi = prctile(finiteResidual, 98);
    else
        robustSigma = 1.4826 * madValue;
        lo = medianValue - residualConfig.robustSigmaMultiplier * robustSigma;
        hi = medianValue + residualConfig.robustSigmaMultiplier * robustSigma;
    end
    residual = finiteResidual(finiteResidual >= lo & finiteResidual <= hi);
end

function teaching = buildTeachingTimeline(nav, normalResidualMGs, config)
    % Формирование учебной временной шкалы: один реальный навигационный фрагмент
    % переносится в несколько заданных дат, сохраняя внутренние интервалы времени.
    segmentStarts = [
        datetime(2026, 1, 12, 9, 0, 0, "TimeZone", "UTC")
        datetime(2026, 1, 18, 11, 30, 0, "TimeZone", "UTC")
        datetime(2026, 1, 25, 15, 0, 0, "TimeZone", "UTC")
        datetime(2026, 2, 10, 8, 15, 0, "TimeZone", "UTC")
        datetime(2026, 3, 7, 10, 0, 0, "TimeZone", "UTC")
        datetime(2026, 3, 21, 17, 45, 0, "TimeZone", "UTC")
        datetime(2026, 4, 13, 12, 0, 0, "TimeZone", "UTC")
        datetime(2026, 5, 4, 7, 30, 0, "TimeZone", "UTC")
        datetime(2026, 5, 11, 14, 20, 0, "TimeZone", "UTC")
        datetime(2026, 5, 19, 19, 10, 0, "TimeZone", "UTC")
        datetime(2026, 5, 27, 5, 50, 0, "TimeZone", "UTC")
        datetime(2026, 6, 16, 16, 40, 0, "TimeZone", "UTC")
        ];

    % Ниже список по умолчанию заменяется значениями из config, чтобы даты
    % можно было изменять без правки основной логики генерации.
    segmentStarts = config.segmentStarts(:);
    sourceRelSeconds = seconds(nav.timeUtc - nav.timeUtc(1));
    rowCount = height(nav) * numel(segmentStarts);

    sampleId = (1:rowCount).';
    timestampUtc = NaT(rowCount, 1, "TimeZone", "UTC");
    monthBlock = strings(rowCount, 1);
    segmentId = strings(rowCount, 1);
    sourceDataset = repmat(string(config.sourceDataset), rowCount, 1);
    altitudeKm = zeros(rowCount, 1);
    latitudeDeg = zeros(rowCount, 1);
    longitudeDeg = zeros(rowCount, 1);
    residualMGs = zeros(rowCount, 1);

    cursor = 1;
    for s = 1:numel(segmentStarts)
        idx = cursor:(cursor + height(nav) - 1);
        timestampUtc(idx) = segmentStarts(s) + seconds(sourceRelSeconds);
        monthBlock(idx) = string(datestr(segmentStarts(s), "yyyy-mm"));
        segmentId(idx) = "segment_" + string(s);
        altitudeKm(idx) = nav.altitudeM / 1000;
        latitudeDeg(idx) = nav.latitudeDeg;
        % Долгота сдвигается между сегментами, чтобы учебные треки не лежали
        % полностью друг на друге на карте.
        longitudeDeg(idx) = wrapTo180Local(nav.longitudeDeg + (s - 1) * config.longitudeShiftPerSegmentDeg);

        % Остатки берутся циклически со сдвигом: так сохраняется реалистичная
        % структура ошибки, но разные сегменты получают разные участки остатка.
        residualStart = mod((s - 1) * config.residual.shiftStep, numel(normalResidualMGs)) + 1;
        residualIdx = mod((residualStart - 1):(residualStart + height(nav) - 2), numel(normalResidualMGs)) + 1;
        residualMGs(idx) = applyResidualConfig(normalResidualMGs(residualIdx), config.residual);
        cursor = cursor + height(nav);
    end

    teaching = table(sampleId, timestampUtc, monthBlock, segmentId, sourceDataset, ...
        altitudeKm, latitudeDeg, longitudeDeg, residualMGs);
end

function lon = wrapTo180Local(lon)
    % Приведение долготы к стандартному диапазону [-180, 180].
    lon = mod(lon + 180, 360) - 180;
end

function [teaching, anomalies] = injectTeachingAnomalies(teaching, config)
    % Управляемые учебные аномалии добавляются из конфигурации. Это делает
    % генератор настраиваемым: можно менять тип, место и амплитуду аномалии.
    anomalyRows = strings(0, 9);

    if config.injectAnomalies
        for anomalyIndex = 1:numel(config.anomalies)
            anomaly = config.anomalies(anomalyIndex);
            if anomaly.enabled
                [teaching, anomalyRows] = applyConfiguredAnomaly(teaching, anomalyRows, anomaly);
            end
        end
    end

    anomalies = array2table(anomalyRows, "VariableNames", ...
        ["anomaly_id", "anomaly_type", "start_time_utc", "end_time_utc", ...
        "affected_columns", "injection_method", "severity", ...
        "expected_student_observation", "teacher_note"]);
    return;

    % Ниже оставлен старый вариант с жестко заданными аномалиями. Из-за return
    % он не выполняется и служит только как историческая справка/шаблон.
    [teaching, anomalyRows] = addAltitudeJump(teaching, anomalyRows, "A001", "segment_2", 120, 132, 65, "easy");
    [teaching, anomalyRows] = addLatitudeLongitudeJump(teaching, anomalyRows, "A002", "segment_4", 260, 270, 42, -95, "easy");
    [teaching, anomalyRows] = addMagneticSpike(teaching, anomalyRows, "A003", "segment_5", 310, 314, 180, "easy");
    [teaching, anomalyRows] = addMagneticDrop(teaching, anomalyRows, "A004", "segment_7", 180, 205, -130, "medium");
    [teaching, anomalyRows] = addMagneticStep(teaching, anomalyRows, "A005", "segment_9", 420, 500, 55, "medium");
    [teaching, anomalyRows] = addNaNBlock(teaching, anomalyRows, "A006", "segment_10", 90, 96, "hard");
    [teaching, anomalyRows] = addZeroMagneticRows(teaching, anomalyRows, "A007", "segment_11", 540, 545, "medium");
    [teaching, anomalyRows] = addZeroTimestamp(teaching, anomalyRows, "A008", "segment_12", 360, 362, "hard");

    anomalies = array2table(anomalyRows, "VariableNames", ...
        ["anomaly_id", "anomaly_type", "start_time_utc", "end_time_utc", ...
        "affected_columns", "injection_method", "severity", ...
        "expected_student_observation", "teacher_note"]);
end

function teachingOutput = makeTeachingOutputTable(teaching)
    % Формирование итоговой таблицы с понятными именами столбцов для CSV.
    teachingOutput = table( ...
        teaching.sampleId, teaching.timestampUtc, teaching.monthBlock, teaching.segmentId, teaching.sourceDataset, ...
        teaching.altitudeKm, teaching.latitudeDeg, teaching.longitudeDeg, teaching.residualMGs, ...
        teaching.BxModelNT, teaching.ByModelNT, teaching.BzModelNT, teaching.BModelNT, teaching.BModelMGs, ...
        teaching.BTeachingMGs, teaching.BxTeachingMGs, teaching.ByTeachingMGs, teaching.BzTeachingMGs, ...
        teaching.isAnomaly, teaching.anomalyType, teaching.anomalyId, teaching.qualityFlag, ...
        'VariableNames', ["sample_id", "timestamp_utc", "month_block", "segment_id", "source_dataset", ...
        "altitude_km", "latitude_deg", "longitude_deg", "residual_mGs", ...
        "Bx_model_nT", "By_model_nT", "Bz_model_nT", "B_model_nT", "B_model_mGs", ...
        "B_teaching_mGs", "Bx_teaching_mGs", "By_teaching_mGs", "Bz_teaching_mGs", ...
        "is_anomaly", "anomaly_type", "anomaly_id", "quality_flag"]);
end

function teaching = addTeachingVectorComponents(teaching)
    % Учебное трехосевое разложение использует направление вектора IGRF и
    % масштабируется по сгенерированному модулю. Это имитация формата данных,
    % а не строгая модель датчика в связанной системе координат спутника.
    BxModelMGs = teaching.BxModelNT * 0.01;
    ByModelMGs = teaching.ByModelNT * 0.01;
    BzModelMGs = teaching.BzModelNT * 0.01;

    % Масштаб показывает, во сколько раз учебный модуль отличается от
    % модельного. Для NaN, нулей и некорректных значений масштаб отключается.
    scale = teaching.BTeachingMGs ./ teaching.BModelMGs;
    invalidScale = ~isfinite(scale) | ~isfinite(teaching.BTeachingMGs) | ...
        ~isfinite(teaching.BModelMGs) | teaching.BModelMGs == 0;
    scale(invalidScale) = NaN;

    teaching.BxTeachingMGs = BxModelMGs .* scale;
    teaching.ByTeachingMGs = ByModelMGs .* scale;
    teaching.BzTeachingMGs = BzModelMGs .* scale;
end

function writeRawLikeFiles(teaching, outputRawLikeDir)
    % Экспорт в формат, похожий на исходные файлы задания: отдельный TXT
    % магнитометра без заголовка и CSV навигации с разделителем ';'.
    timeMs = round(posixtime(teaching.timestampUtc) * 1000);
    % Для аномалии поврежденной временной метки raw-like файл получает
    % time_ms = 0, как в типичном поврежденном телеметрическом поле.
    zeroTimestampRows = teaching.anomalyType == "zero_timestamp";
    timeMs(zeroTimestampRows) = 0;

    magneticMatrix = [timeMs, teaching.BxTeachingMGs, teaching.ByTeachingMGs, teaching.BzTeachingMGs];
    writematrix(magneticMatrix, fullfile(outputRawLikeDir, "teaching_magn_semisynth.txt"), ...
        "FileType", "text", "Delimiter", "tab");

    rtcText = strings(height(teaching), 1);
    for i = 1:height(teaching)
        if zeroTimestampRows(i)
            rtcText(i) = "01-01-1970 00:00:00:000";
        else
            rtcText(i) = string(teaching.timestampUtc(i), "dd-MM-uuuu HH:mm:ss:SSS");
        end
    end

    navOut = table(rtcText, timeMs, teaching.altitudeKm * 1000, teaching.latitudeDeg, teaching.longitudeDeg, ...
        'VariableNames', ["RTC", "RTC ms", "alt m", "lat deg", "lon deg"]);
    writetable(navOut, fullfile(outputRawLikeDir, "teaching_lla_semisynth.csv"), ...
        "Delimiter", ";", "FileType", "text");
end

function residualUsed = applyResidualConfig(residualRaw, residualConfig)
    % Настройка остатка: scale управляет амплитудой шума, biasMGs задает
    % постоянное смещение, clip ограничивает слишком большие значения.
    residualUsed = residualRaw * residualConfig.scale + residualConfig.biasMGs;
    if residualConfig.clipEnabled
        clipRange = residualConfig.clipMGs;
        residualUsed = max(min(residualUsed, clipRange(2)), clipRange(1));
    end
end

function [teaching, rows] = applyConfiguredAnomaly(teaching, rows, anomaly)
    % Единый диспетчер аномалий: тип из config определяет, какая функция
    % будет применена к выбранному фрагменту данных.
    switch string(anomaly.type)
        case "altitude_jump"
            [teaching, rows] = addAltitudeJump(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.params.deltaKm, anomaly.severity);
        case "latlon_jump"
            [teaching, rows] = addLatitudeLongitudeJump(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.params.deltaLat, anomaly.params.deltaLon, anomaly.severity);
        case "magnetic_spike"
            [teaching, rows] = addMagneticSpike(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.params.deltaMGs, anomaly.severity);
        case "magnetic_drop"
            [teaching, rows] = addMagneticDrop(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.params.deltaMGs, anomaly.severity);
        case "magnetic_step"
            [teaching, rows] = addMagneticStep(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.params.deltaMGs, anomaly.severity);
        case "nan_block"
            [teaching, rows] = addNaNBlock(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.severity);
        case "zero_magnetic_rows"
            [teaching, rows] = addZeroMagneticRows(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.severity);
        case "zero_timestamp"
            [teaching, rows] = addZeroTimestamp(teaching, rows, anomaly.id, anomaly.segmentId, ...
                anomaly.localStart, anomaly.localEnd, anomaly.severity);
        otherwise
            error("Unsupported teaching anomaly type: %s", anomaly.type);
    end
end

function [teaching, rows] = addAltitudeJump(teaching, rows, id, segmentId, localStart, localEnd, deltaKm, severity)
    % Навигационная аномалия: резкий скачок высоты внутри выбранного сегмента.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.altitudeKm(idx) = teaching.altitudeKm(idx) + deltaKm;
    [teaching, rows] = markAnomaly(teaching, rows, id, "altitude_jump", idx, ...
    "altitude_km", sprintf("altitude_km = altitude_km + %.1f", deltaKm), severity, ...
    "Sudden unrealistic altitude discontinuity.", ...
    "Good for checking orbital altitude continuity.");
end

function [teaching, rows] = addLatitudeLongitudeJump(teaching, rows, id, segmentId, localStart, localEnd, deltaLat, deltaLon, severity)
    % Навигационная аномалия: скачок широты и долготы, заметный на наземном треке.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.latitudeDeg(idx) = max(min(teaching.latitudeDeg(idx) + deltaLat, 89.5), -89.5);
    teaching.longitudeDeg(idx) = wrapTo180Local(teaching.longitudeDeg(idx) + deltaLon);
    [teaching, rows] = markAnomaly(teaching, rows, id, "latlon_jump", idx, ...
        "latitude_deg;longitude_deg", sprintf("lat += %.1f, lon += %.1f", deltaLat, deltaLon), severity, ...
        "Ground track suddenly moves to an inconsistent location.", "Good for map-based continuity analysis.");
end

function [teaching, rows] = addMagneticSpike(teaching, rows, id, segmentId, localStart, localEnd, deltaMGs, severity)
    % Магнитометрическая аномалия: короткий положительный выброс модуля поля.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.BTeachingMGs(idx) = teaching.BTeachingMGs(idx) + deltaMGs;
    [teaching, rows] = markAnomaly(teaching, rows, id, "magnetic_spike", idx, ...
        "B_teaching_mGs", sprintf("B_teaching_mGs += %.1f", deltaMGs), severity, ...
        "Short high magnetic-field spike.", "Visible in |B| time series.");
end

function [teaching, rows] = addMagneticDrop(teaching, rows, id, segmentId, localStart, localEnd, deltaMGs, severity)
    % Магнитометрическая аномалия: локальное падение модуля поля.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.BTeachingMGs(idx) = max(teaching.BTeachingMGs(idx) + deltaMGs, 0);
    [teaching, rows] = markAnomaly(teaching, rows, id, "magnetic_drop", idx, ...
        "B_teaching_mGs", sprintf("B_teaching_mGs += %.1f", deltaMGs), severity, ...
        "Local magnetic-field depression.", "Requires comparing with local trend or IGRF baseline.");
end

function [teaching, rows] = addMagneticStep(teaching, rows, id, segmentId, localStart, localEnd, deltaMGs, severity)
    % Магнитометрическая аномалия: длительное ступенчатое смещение.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.BTeachingMGs(idx) = teaching.BTeachingMGs(idx) + deltaMGs;
    [teaching, rows] = markAnomaly(teaching, rows, id, "magnetic_step", idx, ...
        "B_teaching_mGs", sprintf("constant offset %.1f mGs", deltaMGs), severity, ...
        "Longer step-like magnetic-field offset.", "Good for residual analysis against IGRF.");
end

function [teaching, rows] = addNaNBlock(teaching, rows, id, segmentId, localStart, localEnd, severity)
    % Аномалия качества данных: блок пропущенных магнитных значений.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.BTeachingMGs(idx) = NaN;
    [teaching, rows] = markAnomaly(teaching, rows, id, "nan_block", idx, ...
        "B_teaching_mGs", "set to NaN", severity, ...
        "Missing magnetic values.", "Good for basic data-quality checks.");
end

function [teaching, rows] = addZeroMagneticRows(teaching, rows, id, segmentId, localStart, localEnd, severity)
    % Аномалия качества данных: строки с нулевым модулем магнитного поля.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.BTeachingMGs(idx) = 0;
    [teaching, rows] = markAnomaly(teaching, rows, id, "zero_magnetic_rows", idx, ...
        "B_teaching_mGs", "set to zero", severity, ...
        "Magnetic values become exactly zero.", "Mimics invalid all-zero measurements.");
end

function [teaching, rows] = addZeroTimestamp(teaching, rows, id, segmentId, localStart, localEnd, severity)
    % Аномалия времени: имитация поврежденной временной метки через Unix epoch.
    idx = localSegmentIndex(teaching, segmentId, localStart, localEnd);
    teaching.timestampUtc(idx) = datetime(1970, 1, 1, 0, 0, 0, "TimeZone", "UTC");
    [teaching, rows] = markAnomaly(teaching, rows, id, "zero_timestamp", idx, ...
        "timestamp_utc", "timestamp replaced by Unix epoch", severity, ...
        "Time suddenly jumps to the epoch.", "Represents timestamp corruption.");
end

function idx = localSegmentIndex(teaching, segmentId, localStart, localEnd)
    % Перевод локальных номеров внутри segment_id в реальные индексы строк
    % итоговой таблицы.
    segmentRows = find(teaching.segmentId == segmentId);
    localStart = max(localStart, 1);
    localEnd = min(localEnd, numel(segmentRows));
    idx = segmentRows(localStart:localEnd);
end

function [teaching, rows] = markAnomaly(teaching, rows, id, type, idx, columns, method, severity, observation, note)
    % Одновременно размечает строки в основной таблице и добавляет запись
    % в таблицу описания аномалий для преподавательской проверки.
    teaching.isAnomaly(idx) = true;
    teaching.anomalyType(idx) = type;
    teaching.anomalyId(idx) = id;
    teaching.qualityFlag(idx) = "injected_anomaly";

    startTime = string(teaching.timestampUtc(idx(1)), "yyyy-MM-dd'T'HH:mm:ss'Z'");
    endTime = string(teaching.timestampUtc(idx(end)), "yyyy-MM-dd'T'HH:mm:ss'Z'");
    rows(end + 1, :) = [id, type, startTime, endTime, columns, method, severity, observation, note]; %#ok<AGROW>
end

function writeMetadata(outputDataDir, rowCount, anomalyCount, magFile, navFile, config)
    % metadata.json фиксирует параметры генерации, чтобы учебный набор можно
    % было воспроизвести и проверить после изменения config.
    metadata = struct();
    metadata.dataset_name = "Polytech-Universe teaching semi-synthetic magnetic dataset";
    metadata.created_utc = char(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
    metadata.generator = "Скрипты/02_учебный_набор/generate_teaching_dataset.m";
    metadata.random_seed = config.randomSeed;
    metadata.randomSeed = config.randomSeed;
    metadata.sourceDataset = config.sourceDataset;
    metadata.magnetic_model = "IGRF-14 via MATLAB igrfmagm";
    [~, magName, magExt] = fileparts(magFile);
    [~, navName, navExt] = fileparts(navFile);
    metadata.source_magnetometer_file = [magName, magExt];
    metadata.source_navigation_file = [navName, navExt];
    metadata.row_count = rowCount;
    metadata.anomaly_count = anomalyCount;
    metadata.segmentStarts = cellstr(string(config.segmentStarts, "yyyy-MM-dd'T'HH:mm:ss'Z'"));
    metadata.longitudeShiftPerSegmentDeg = config.longitudeShiftPerSegmentDeg;
    metadata.residual = struct();
    metadata.residual.mode = config.residual.mode;
    metadata.residual.robustSigmaMultiplier = config.residual.robustSigmaMultiplier;
    metadata.residual.shiftStep = config.residual.shiftStep;
    metadata.residual.scale = config.residual.scale;
    metadata.residual.biasMGs = config.residual.biasMGs;
    metadata.residual.clipEnabled = config.residual.clipEnabled;
    metadata.residual.clipMGs = config.residual.clipMGs;
    metadata.injectAnomalies = config.injectAnomalies;
    metadata.units.time = "UTC";
    metadata.units.altitude = "km";
    metadata.units.latitude_longitude = "deg";
    metadata.units.magnetic_field_model = "nT and mGs";
    metadata.note = "Educational semi-synthetic dataset. Not a scientific observation product.";

    jsonText = jsonencode(metadata, "PrettyPrint", true);
    fid = fopen(fullfile(outputDataDir, "metadata.json"), "w", "n", "UTF-8");
    if fid < 0
        error("Could not write metadata.json");
    end
    fprintf(fid, "%s\n", jsonText);
    fclose(fid);
end

function plotTeachingDataset(teaching, outputFigureDir)
    % Быстрые контрольные графики нужны для проверки результата генерации:
    % наземный трек, сравнение IGRF/учебного |B| и распределение остатков.
    fig = plotUnifiedGroundTrackMap(teaching.longitudeDeg, teaching.latitudeDeg, teaching.altitudeKm, ...
        "Наземный трек учебного набора данных с цветовым отображением высоты", ...
        "Высота, км");
    exportgraphics(fig, fullfile(outputFigureDir, "ground_track.png"), "Resolution", 300);
    close(fig);

    fig = figure("Visible", "off", "Color", "w", "Position", [100 100 1200 520]);
    % Поврежденные временные метки могут попасть в 1970 год, поэтому для
    % обзорного графика магнитного поля оставляются только учебные даты 2026.
    plotMask = year(teaching.timestampUtc) == 2026;
    plot(teaching.timestampUtc(plotMask), teaching.BModelMGs(plotMask), "Color", [0.2 0.2 0.2], "LineWidth", 0.7);
    hold on;
    plot(teaching.timestampUtc(plotMask), teaching.BTeachingMGs(plotMask), "Color", [0.05 0.25 0.65], "LineWidth", 0.8);
    anomalyMask = teaching.isAnomaly & isfinite(teaching.BTeachingMGs) & plotMask;
    scatter(teaching.timestampUtc(anomalyMask), teaching.BTeachingMGs(anomalyMask), 18, "r", "filled");
    xlabel("Time, UTC");
    ylabel("|B|, mGs");
    title("IGRF baseline, residuals and injected magnetic anomalies");
    legend("IGRF model", "Teaching |B|", "Injected anomalies", "Location", "best");
    grid on;
    xlim([datetime(2026, 1, 1, "TimeZone", "UTC"), datetime(2026, 7, 1, "TimeZone", "UTC")]);
    exportgraphics(fig, fullfile(outputFigureDir, "magnetic_field_with_anomalies.png"), "Resolution", 300);
    close(fig);

    fig = figure("Visible", "off", "Color", "w", "Position", [120 120 1200 520]);
    histogram(teaching.residualMGs, 40);
    xlabel("Residual, mGs");
    ylabel("Count");
    title("Distribution of real residuals added to IGRF model");
    grid on;
    exportgraphics(fig, fullfile(outputFigureDir, "residual_distribution.png"), "Resolution", 300);
    close(fig);
end

function drawWorldMapBackground()
    % Единый простой фон мировой карты: береговые линии MATLAB coastlines.
    % Такой подход сохраняет одинаковый стиль с другими lon-lat графиками проекта.
    try
        coast = load("coastlines");
        plot(coast.coastlon, coast.coastlat, "Color", [0.68 0.68 0.68], "LineWidth", 0.5);
    catch
        fprintf("Warning: coastlines data is unavailable; map background is skipped.\n");
    end
end

function formatWorldMapAxes()
    % Фиксированные границы карты позволяют сравнивать общие и сегментные
    % графики в одной системе координат.
    xlim([-180 180]);
    ylim([-90 90]);
    pbaspect([2 1 1]);
    grid on;
    box on;
end

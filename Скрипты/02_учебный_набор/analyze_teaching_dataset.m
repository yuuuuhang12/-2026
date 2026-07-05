%% Анализ и визуализация учебного спутникового набора данных
% Русское название: Анализ учебного набора данных для обучения.
% Скрипт читает "Задание 2 · Данные для обучения/data/teaching_satellite_dataset.csv"
% и строит отчетные графики, не изменяя исходную таблицу.

clear; clc; close all;

config = defaultAnalysisConfig();
config = resolveProjectPaths(config);

%% Чтение и нормализация входных таблиц
% Загружается основной учебный CSV, дополнительное описание аномалий и
% приводятся типы столбцов к формату, удобному для построения графиков.
teaching = readTeachingDataset(config.datasetCsv);
anomalyDescription = readAnomalyDescription(config.anomalyCsv);
teaching = prepareTeachingTable(teaching);

if ~exist(config.outputFigureDir, "dir")
    mkdir(config.outputFigureDir);
end

checkRawLikeFiles(config);
groups = getSegmentGroups(teaching, config);
createdFigures = strings(0, 1);

%% Построение обзорных и посегментных графиков
% Создаются графики временного покрытия, наземных треков, магнитного поля,
% остатка модели и сводки по размеченным аномалиям.
createdFigures(end + 1, 1) = plotTimeSegmentsOverview(teaching, groups, config);
createdFigures(end + 1, 1) = plotGroundTrackByAltitude(teaching, config);
createdFigures(end + 1, 1) = plotGroundTrackByB(teaching, config);
createdFigures = [createdFigures; plotGroundTrackByAltitudePerSegment(teaching, groups, config)]; %#ok<AGROW>
createdFigures = [createdFigures; plotGroundTrackByBPerSegment(teaching, groups, config)]; %#ok<AGROW>
createdFigures(end + 1, 1) = plotMagneticNormTimeAll(teaching, config);
createdFigures = [createdFigures; plotMagneticNormTimePerSegment(teaching, groups, config)]; %#ok<AGROW>
createdFigures(end + 1, 1) = plotResidualTime(teaching, config);

[anomalyFigure, anomalyFigureCreated, anomalySkipReason] = plotAnomalySummary(teaching, config);
if anomalyFigureCreated
    createdFigures(end + 1, 1) = anomalyFigure;
end

printAnalysisSummary(teaching, groups, createdFigures, config, anomalyDescription, anomalySkipReason);

%% Локальные функции

% Формирует конфигурацию анализа: пути к входным таблицам, режим отображения
% учительских меток, параметры сохранения рисунков и нижнюю границу валидного
% времени. Все основные настройки визуализации удобно менять здесь.
function config = defaultAnalysisConfig()
    config = struct();
    datasetRootDir = "Задание 2 · Данные для обучения";
    config.datasetCsv = fullfile(datasetRootDir, "data", "teaching_satellite_dataset.csv");
    config.anomalyCsv = fullfile(datasetRootDir, "data", "anomaly_description.csv");
    config.rawLikeMagFile = fullfile(datasetRootDir, "raw_like", "teaching_magn_semisynth.txt");
    config.rawLikeNavFile = fullfile(datasetRootDir, "raw_like", "teaching_lla_semisynth.csv");
    config.outputFigureDir = fullfile(datasetRootDir, "analysis_figures");
    config.showTeacherLabels = true;
    config.saveDpi = 300;
    config.figureVisible = "off";
    config.maxGroundTrackPoints = 50000;
    config.validGenerationStartUtc = datetime(2026, 1, 1, 0, 0, 0, "TimeZone", "UTC");
end

% Определяет корневую папку проекта независимо от того, откуда запущен скрипт:
% из корня репозитория, из папки "Скрипты/02_учебный_набор" или из текущей рабочей директории MATLAB.
% После нахождения корня все относительные пути переводятся в абсолютные.
function config = resolveProjectPaths(config)
    scriptDir = fileparts(mfilename("fullpath"));
    if isempty(scriptDir)
        scriptDir = pwd;
    end
    scriptsRootDir = fileparts(scriptDir);
    repoDirFromScript = fileparts(scriptsRootDir);
    commonScriptDir = fullfile(scriptsRootDir, "03_общие_функции");
    if exist(commonScriptDir, "dir"); addpath(commonScriptDir); end

    % Проверяются наиболее вероятные места запуска: корень репозитория,
    % сама папка скрипта и текущая рабочая директория MATLAB.
    candidateRoots = [
        string(repoDirFromScript)
        string(fileparts(scriptDir))
        string(scriptDir)
        string(pwd)
        ];

    repoDir = "";
    for k = 1:numel(candidateRoots)
        candidate = candidateRoots(k);
        if isfile(fullfile(candidate, config.datasetCsv))
            repoDir = candidate;
            break;
        end
    end

    if strlength(repoDir) == 0
        error("Could not find teaching dataset CSV. Run from repository root or Скрипты/02_учебный_набор.");
    end

    config.repoDir = repoDir;
    config.datasetCsv = fullfile(repoDir, config.datasetCsv);
    config.anomalyCsv = fullfile(repoDir, config.anomalyCsv);
    config.rawLikeMagFile = fullfile(repoDir, config.rawLikeMagFile);
    config.rawLikeNavFile = fullfile(repoDir, config.rawLikeNavFile);
    config.outputFigureDir = fullfile(repoDir, config.outputFigureDir);
end

% Читает основную таблицу учебного набора данных. Имена столбцов сохраняются
% без автоматического переименования, так как дальше код ожидает конкретные
% поля: timestamp_utc, altitude_km, B_model_mGs, B_teaching_mGs и др.
function teaching = readTeachingDataset(datasetCsv)
    if ~isfile(datasetCsv)
        error("Teaching dataset CSV not found: %s", datasetCsv);
    end
    teaching = readtable(datasetCsv, "VariableNamingRule", "preserve");
end

% Читает таблицу описания аномалий, если она существует. Этот файл считается
% дополнительным: его отсутствие не должно мешать построению основных графиков.
function anomalyDescription = readAnomalyDescription(anomalyCsv)
    if isfile(anomalyCsv)
        anomalyDescription = readtable(anomalyCsv, "VariableNamingRule", "preserve");
    else
        fprintf("Optional anomaly description not found: %s\n", anomalyCsv);
        anomalyDescription = table();
    end
end

% Приводит таблицу к единому внутреннему формату:
% проверяет обязательные столбцы, преобразует время в datetime, числовые поля
% в double, а также добавляет служебные поля, если они отсутствуют в CSV.
function teaching = prepareTeachingTable(teaching)
    % Минимальный набор столбцов, без которого невозможно построить основные графики.
    requiredColumns = ["timestamp_utc", "sample_id", "altitude_km", "latitude_deg", ...
        "longitude_deg", "B_model_mGs", "B_teaching_mGs"];
    assertRequiredColumns(teaching, requiredColumns);

    teaching.timestamp_utc = parseUtcDatetime(teaching.timestamp_utc);

    % Числовые столбцы явно приводятся к double для корректной работы plot/scatter.
    numericColumns = ["sample_id", "altitude_km", "latitude_deg", "longitude_deg", ...
        "B_model_mGs", "B_teaching_mGs"];
    for k = 1:numel(numericColumns)
        teaching.(numericColumns(k)) = toDoubleColumn(teaching.(numericColumns(k)));
    end

    if ~ismember("segment_id", string(teaching.Properties.VariableNames))
        teaching.segment_id = "date_" + string(dateshift(teaching.timestamp_utc, "start", "day"), "yyyy_MM_dd");
    else
        teaching.segment_id = string(teaching.segment_id);
    end

    if ~ismember("month_block", string(teaching.Properties.VariableNames))
        teaching.month_block = string(teaching.timestamp_utc, "yyyy-MM");
    else
        teaching.month_block = string(teaching.month_block);
    end

    % Контрольный остаток пересчитывается из двух основных магнитных столбцов,
    % если генератор не записал его заранее.
    if ~ismember("residual_check_mGs", string(teaching.Properties.VariableNames))
        teaching.residual_check_mGs = teaching.B_teaching_mGs - teaching.B_model_mGs;
    else
        teaching.residual_check_mGs = toDoubleColumn(teaching.residual_check_mGs);
    end

    if ~ismember("is_anomaly", string(teaching.Properties.VariableNames))
        teaching.is_anomaly = false(height(teaching), 1);
    else
        teaching.is_anomaly = logical(toDoubleColumn(teaching.is_anomaly));
    end

    if ~ismember("anomaly_type", string(teaching.Properties.VariableNames))
        teaching.anomaly_type = repmat("normal", height(teaching), 1);
    else
        teaching.anomaly_type = string(teaching.anomaly_type);
        teaching.anomaly_type(strlength(teaching.anomaly_type) == 0) = "normal";
    end

    if ~ismember("anomaly_id", string(teaching.Properties.VariableNames))
        teaching.anomaly_id = strings(height(teaching), 1);
    else
        teaching.anomaly_id = string(teaching.anomaly_id);
    end
end

% Проверяет наличие обязательных столбцов. Если хотя бы один столбец отсутствует,
% анализ прерывается с понятным сообщением, чтобы ошибка не проявилась позже
% в виде неочевидного сбоя при построении графиков.
function assertRequiredColumns(T, names)
    available = string(T.Properties.VariableNames);
    missing = names(~ismember(names, available));
    if ~isempty(missing)
        error("Teaching dataset is missing required columns: %s", strjoin(missing, ", "));
    end
end

% Преобразует столбец времени в datetime с часовым поясом UTC. Сначала
% используется ожидаемый формат, затем MATLAB получает возможность распознать
% строку автоматически. Это повышает устойчивость к небольшим отличиям CSV.
function dt = parseUtcDatetime(values)
    if isdatetime(values)
        dt = values;
    else
        textValues = string(values);
        try
            dt = datetime(textValues, "InputFormat", "yyyy-MM-dd HH:mm:ss", "TimeZone", "UTC");
        catch
            dt = datetime(textValues, "TimeZone", "UTC");
        end
    end
    if isempty(dt.TimeZone)
        dt.TimeZone = "UTC";
    end
end

% Универсально переводит числовой, логический или строковый столбец в double.
% Это нужно, потому что readtable иногда считывает численные CSV-поля как строки.
function values = toDoubleColumn(values)
    if isnumeric(values) || islogical(values)
        values = double(values);
    else
        values = str2double(string(values));
    end
end

% Проверяет наличие raw-like файлов. Они не используются для построения графиков,
% но сообщение в консоли помогает убедиться, что генератор создал оба формата данных.
function checkRawLikeFiles(config)
    if isfile(config.rawLikeMagFile)
        fprintf("Raw-like magnetometer file found: %s\n", config.rawLikeMagFile);
    else
        fprintf("Raw-like magnetometer file not found: %s\n", config.rawLikeMagFile);
    end

    if isfile(config.rawLikeNavFile)
        fprintf("Raw-like navigation file found: %s\n", config.rawLikeNavFile);
    else
        fprintf("Raw-like navigation file not found: %s\n", config.rawLikeNavFile);
    end
end

% Формирует группы по segment_id. Для каждой группы сохраняется маска строк,
% безопасная метка даты и строка для заголовков. При определении даты намеренно
% игнорируются поврежденные временные метки, например 1970-01-01.
function groups = getSegmentGroups(teaching, config)
    segmentNames = unique(teaching.segment_id, "stable");
    groups = struct("name", {}, "mask", {}, "dateTag", {}, "titleDate", {});
    for k = 1:numel(segmentNames)
        mask = teaching.segment_id == segmentNames(k);
        validTime = teaching.timestamp_utc(mask & isValidGenerationTime(teaching.timestamp_utc, config));
        if isempty(validTime)
            dateTag = "unknown_date";
            titleDate = "unknown date";
        else
            firstTime = min(validTime);
            dateTag = string(firstTime, "yyyy_MM_dd");
            titleDate = string(firstTime, "yyyy-MM-dd");
        end
        groups(k).name = segmentNames(k); %#ok<AGROW>
        groups(k).mask = mask; %#ok<AGROW>
        groups(k).dateTag = dateTag; %#ok<AGROW>
        groups(k).titleDate = titleDate; %#ok<AGROW>
    end
end

% Возвращает маску аномальных точек только в режиме учительских меток.
% Если showTeacherLabels = false, графики не раскрывают заранее правильные ответы.
function mask = getAnomalyMask(teaching, config)
    if config.showTeacherLabels && ismember("is_anomaly", string(teaching.Properties.VariableNames))
        mask = teaching.is_anomaly == true;
    else
        mask = false(height(teaching), 1);
    end
end

% Отделяет реальные сгенерированные даты от поврежденных временных меток.
% Например, timestamp = 1970-01-01 используется как учебная ошибка и не должен
% расширять общий диапазон оси времени на десятилетия назад.
function mask = isValidGenerationTime(timestampUtc, config)
    mask = ~isnat(timestampUtc) & timestampUtc >= config.validGenerationStartUtc;
end

% Возвращает общий временной диапазон для обзорных графиков. Нижняя граница
% фиксируется настройкой validGenerationStartUtc, а верхняя округляется до начала
% следующего месяца, чтобы общий график выглядел аккуратно.
function [timeStart, timeEnd] = getGeneratedTimeWindow(teaching, config)
    validTime = teaching.timestamp_utc(isValidGenerationTime(teaching.timestamp_utc, config));
    timeStart = config.validGenerationStartUtc;
    if isempty(validTime)
        timeEnd = datetime(2026, 2, 1, 0, 0, 0, "TimeZone", "UTC");
    else
        maxMonth = dateshift(max(validTime), "start", "month");
        timeEnd = dateshift(maxMonth, "start", "month", "next");
    end
end

% Определяет временное окно для набора сегментов на основе валидных дат.
% Используется там, где нужно показать общий диапазон без учета поврежденных меток.
function [timeStart, timeEnd] = getSegmentTimeWindow(teaching, config)
    validTime = teaching.timestamp_utc(isValidGenerationTime(teaching.timestamp_utc, config));
    if isempty(validTime)
        [timeStart, timeEnd] = getGeneratedTimeWindow(teaching, config);
    else
        timeStart = dateshift(min(validTime), "start", "day");
        timeEnd = dateshift(max(validTime), "start", "day") + days(1);
    end
end

% Подбирает локальное окно времени для одного сегмента. Это важно для посегментных
% графиков: короткий фрагмент не должен сжиматься в тонкую линию на оси,
% рассчитанной для всего шестимесячного набора.
function [timeStart, timeEnd] = getLocalTimeWindow(segmentTable, config)
    % Выбирается окно оси X, соответствующее фактической длительности сегмента.
    validTime = segmentTable.timestamp_utc(isValidGenerationTime(segmentTable.timestamp_utc, config));

    if isempty(validTime)
        [timeStart, timeEnd] = getGeneratedTimeWindow(segmentTable, config);
        return;
    end

    timeStart = min(validTime);
    timeEnd = max(validTime);

    if timeEnd <= timeStart
        % Вырожденный случай: в сегменте есть только одна валидная временная метка.
        timeStart = timeStart - hours(1);
        timeEnd = timeEnd + hours(1);
        return;
    end

    timeSpan = timeEnd - timeStart;
    padding = 0.05 * timeSpan;
    if padding < minutes(5)
        padding = minutes(5);
    end

    timeStart = timeStart - padding;
    timeEnd = timeEnd + padding;
end

% Настраивает формат подписей времени в зависимости от длительности интервала:
% для коротких фрагментов показываются часы и минуты, для длинных — календарные даты.
function applyAdaptiveTimeAxis(ax, timeStart, timeEnd)
    % Формат подписей datetime выбирается так, чтобы он был читаемым для текущего интервала.
    xlim(ax, [timeStart timeEnd]);
    timeSpan = timeEnd - timeStart;

    if timeSpan <= days(2)
        xtickformat(ax, "HH:mm");
        xlabel(ax, "UTC time, HH:mm");
    elseif timeSpan <= days(45)
        xtickformat(ax, "MM-dd HH:mm");
        xlabel(ax, "UTC time, MM-dd HH:mm");
    else
        xtickformat(ax, "yyyy-MM-dd");
        xlabel(ax, "UTC time");
    end
end

% Строит обзор временного покрытия: каждая точка показывает принадлежность
% записи к сегменту. Этот график нужен для проверки количества сгенерированных
% фрагментов и общего временного диапазона датасета.
function filePath = plotTimeSegmentsOverview(teaching, groups, config)
    fig = createFigure(config, [120 120 1300 620]);
    ax = axes("Parent", fig);
    hold(ax, "on");

    segmentIndex = zeros(height(teaching), 1);
    for k = 1:numel(groups)
        segmentIndex(groups(k).mask) = k;
    end

    validTimeMask = isValidGenerationTime(teaching.timestamp_utc, config);
    scatter(ax, teaching.timestamp_utc(validTimeMask), segmentIndex(validTimeMask), 18, segmentIndex(validTimeMask), "filled");
    yticks(ax, 1:numel(groups));
    yticklabels(ax, arrayfun(@(g) char(g.name), groups, "UniformOutput", false));
    [timeStart, timeEnd] = getGeneratedTimeWindow(teaching, config);
    xlim(ax, [timeStart timeEnd]);
    xlabel(ax, "UTC time");
    ylabel(ax, "Segment");
    title(ax, "Teaching dataset time coverage and segments");
    cb = colorbar(ax);
    cb.Label.String = "Segment number";
    applyCommonStyle(ax);
    filePath = saveFigure(fig, config, "01_time_segments_overview.png");
end

% Строит общий наземный трек с окраской точек по высоте. Используется для
% контроля орбитальной траектории и поиска скачков в навигационных данных.
function filePath = plotGroundTrackByAltitude(teaching, config)
    filePath = plotGroundTrack(teaching, teaching.altitude_km, ...
        "Teaching dataset ground track by altitude", ...
        "Altitude, km", "02_ground_track_by_altitude.png", config);
end

% Строит общий наземный трек с окраской точек по модулю магнитного поля.
% Такая визуализация связывает положение спутника с изменением |B|.
function filePath = plotGroundTrackByB(teaching, config)
    filePath = plotGroundTrack(teaching, teaching.B_teaching_mGs, ...
        "Teaching dataset ground track by magnetic field magnitude", ...
        "|B|, mGs", "03_ground_track_by_B.png", config);
end

% Создает отдельную карту высоты для каждого сгенерированного сегмента.
% Число графиков определяется автоматически по segment_id, поэтому N не задано вручную.
function files = plotGroundTrackByAltitudePerSegment(teaching, groups, config)
    files = strings(0, 1);
    for k = 1:numel(groups)
        segmentTable = teaching(groups(k).mask, :);
        safeSegment = regexprep(char(groups(k).name), "[^A-Za-z0-9_-]", "_");
        fileName = sprintf("02_ground_track_by_altitude_%s_%s.png", safeSegment, groups(k).dateTag);
        plotTitle = sprintf("Ground track by altitude: %s (%s)", groups(k).name, groups(k).titleDate);
        files(end + 1, 1) = plotGroundTrack(segmentTable, segmentTable.altitude_km, ...
            string(plotTitle), "Altitude, km", fileName, config); %#ok<AGROW>
    end
end

% Создает отдельную карту магнитного поля для каждого сгенерированного сегмента.
% Это позволяет рассмотреть отдельные даты без визуального наложения всех треков.
function files = plotGroundTrackByBPerSegment(teaching, groups, config)
    files = strings(0, 1);
    for k = 1:numel(groups)
        segmentTable = teaching(groups(k).mask, :);
        safeSegment = regexprep(char(groups(k).name), "[^A-Za-z0-9_-]", "_");
        fileName = sprintf("03_ground_track_by_B_%s_%s.png", safeSegment, groups(k).dateTag);
        plotTitle = sprintf("Ground track by magnetic field magnitude: %s (%s)", groups(k).name, groups(k).titleDate);
        files(end + 1, 1) = plotGroundTrack(segmentTable, segmentTable.B_teaching_mGs, ...
            string(plotTitle), "|B|, mGs", fileName, config); %#ok<AGROW>
    end
end

% Универсальная функция построения наземного трека. Она передает координаты
% в plotUnifiedGroundTrackMap, чтобы сохранить тот же стиль мировой карты, который
% уже использовался в предыдущих скриптах проекта. Аномалии накладываются сверху
% только в учительском режиме.
function filePath = plotGroundTrack(teaching, colorValue, plotTitle, colorbarLabel, fileName, config)
    % На карту передаются только строки с корректными координатами и значением цвета.
    % Это защищает географический график от NaN и поврежденных числовых полей.
    valid = isfinite(teaching.longitude_deg) & isfinite(teaching.latitude_deg) & isfinite(colorValue);
    fig = plotUnifiedGroundTrackMap(teaching.longitude_deg(valid), teaching.latitude_deg(valid), colorValue(valid), ...
        plotTitle, colorbarLabel, "Visible", config.figureVisible, "MaxPoints", config.maxGroundTrackPoints);

    anomalyMask = getAnomalyMask(teaching, config) & valid;
    if any(anomalyMask)
        try
            hold on;
            scatter(teaching.longitude_deg(anomalyMask), teaching.latitude_deg(anomalyMask), ...
                38, "m", "x", "LineWidth", 1.1, "DisplayName", "Anomalies");
        catch
            fprintf("Warning: could not overlay anomaly markers on ground track.\n");
        end
    end

    filePath = saveFigure(fig, config, fileName);
end

% Строит общий график модуля магнитного поля за весь период: теоретическая
% кривая IGRF сравнивается с учебным полусинтетическим сигналом.
function filePath = plotMagneticNormTimeAll(teaching, config)
    fig = createFigure(config, [100 100 1350 620]);
    ax = axes("Parent", fig);
    plotMagneticNormSeries(ax, teaching, config);
    [timeStart, timeEnd] = getGeneratedTimeWindow(teaching, config);
    xlim(ax, [timeStart timeEnd]);
    title(ax, "Magnetic field magnitude: IGRF model and teaching data");
    filePath = saveFigure(fig, config, "04_magnetic_norm_time_all.png");
end

% Строит графики модуля магнитного поля отдельно для каждого сегмента.
% Для каждого фрагмента используется собственная локальная шкала времени,
% чтобы короткие участки не терялись на общем временном интервале.
function files = plotMagneticNormTimePerSegment(teaching, groups, config)
    % Каждый сегмент строится в собственной локальной шкале времени.
    % Если использовать общий диапазон всего датасета, короткий суточный
    % фрагмент сжимается почти в вертикальную линию.
    files = strings(0, 1);
    for k = 1:numel(groups)
        segmentTable = teaching(groups(k).mask, :);
        fig = createFigure(config, [100 100 1200 540]);
        ax = axes("Parent", fig);
        plotMagneticNormSeries(ax, segmentTable, config);

        [timeStart, timeEnd] = getLocalTimeWindow(segmentTable, config);
        applyAdaptiveTimeAxis(ax, timeStart, timeEnd);

        title(ax, sprintf("Magnetic field magnitude: %s (%s)", groups(k).name, groups(k).titleDate), ...
            "Interpreter", "none");
        safeSegment = regexprep(char(groups(k).name), "[^A-Za-z0-9_-]", "_");
        fileName = sprintf("04_magnetic_norm_time_%s_%s.png", safeSegment, groups(k).dateTag);
        files(end + 1, 1) = saveFigure(fig, config, fileName); %#ok<AGROW>
    end
end

% Рисует две основные кривые магнитного поля на уже созданных осях:
% модельный модуль по IGRF и итоговый учебный модуль. Функция переиспользуется
% как для общего графика, так и для посегментных графиков.
function plotMagneticNormSeries(ax, teaching, config)
    hold(ax, "on");
    validTimeMask = isValidGenerationTime(teaching.timestamp_utc, config);
    plot(ax, teaching.timestamp_utc(validTimeMask), teaching.B_model_mGs(validTimeMask), "-", "LineWidth", 1.0, ...
        "Color", [0.15 0.35 0.7], "DisplayName", "IGRF, mGs");
    plot(ax, teaching.timestamp_utc(validTimeMask), teaching.B_teaching_mGs(validTimeMask), "-", "LineWidth", 0.9, ...
        "Color", [0.75 0.25 0.15], "DisplayName", "Teaching |B|, mGs");

    anomalyMask = getAnomalyMask(teaching, config) & validTimeMask;
    if any(anomalyMask)
        scatter(ax, teaching.timestamp_utc(anomalyMask), teaching.B_teaching_mGs(anomalyMask), ...
            28, "m", "filled", "DisplayName", "Anomalies");
    end

    xlabel(ax, "UTC time");
    ylabel(ax, "|B|, mGs");
    applyCommonStyle(ax);
    legend(ax, "Location", "best");
end

% Строит остаток относительно IGRF: residual_check_mGs = B_teaching_mGs - B_model_mGs.
% Дополнительно выводятся робастные ориентиры median и median ± 3*MAD,
% которые помогают визуально отделять нормальный фон от сильных отклонений.
function filePath = plotResidualTime(teaching, config)
    fig = createFigure(config, [100 100 1350 620]);
    ax = axes("Parent", fig);
    hold(ax, "on");

    residual = teaching.residual_check_mGs;
    validTimeMask = isValidGenerationTime(teaching.timestamp_utc, config);
    plot(ax, teaching.timestamp_utc(validTimeMask), residual(validTimeMask), "-", "LineWidth", 0.8, ...
        "Color", [0.2 0.2 0.2], "DisplayName", "Residual");

    % Робастные ориентиры считаются только по конечным значениям, чтобы NaN-блоки
    % не искажали статистику и не останавливали построение графика.
    finiteResidual = residual(isfinite(residual));
    residualMedian = median(finiteResidual, "omitnan");
    residualMad = median(abs(finiteResidual - residualMedian), "omitnan");
    yline(ax, residualMedian, "-", "Median", "Color", [0.1 0.45 0.1], "LineWidth", 1.1);
    yline(ax, residualMedian + 3 * residualMad, "--", "+3 MAD", "Color", [0.75 0.25 0.1]);
    yline(ax, residualMedian - 3 * residualMad, "--", "-3 MAD", "Color", [0.75 0.25 0.1]);

    anomalyMask = getAnomalyMask(teaching, config) & validTimeMask;
    if any(anomalyMask)
        scatter(ax, teaching.timestamp_utc(anomalyMask), residual(anomalyMask), ...
            28, "m", "filled", "DisplayName", "Anomalies");
    end

    [timeStart, timeEnd] = getGeneratedTimeWindow(teaching, config);
    xlim(ax, [timeStart timeEnd]);
    xlabel(ax, "UTC time");
    ylabel(ax, "Residual, mGs");
    title(ax, "Teaching magnetic field residual relative to IGRF");
    applyCommonStyle(ax);
    legend(ax, "Location", "best");
    filePath = saveFigure(fig, config, "05_residual_time.png");
end

% Строит сводку по типам размеченных аномалий. Если учительские метки отключены
% или в таблице нет аномальных точек, функция корректно пропускает этот график
% и возвращает причину пропуска.
function [filePath, created, skipReason] = plotAnomalySummary(teaching, config)
    filePath = "";
    created = false;
    skipReason = "";

    if ~config.showTeacherLabels
        skipReason = "showTeacherLabels is false";
        fprintf("Skipping anomaly summary: %s\n", skipReason);
        return;
    end

    anomalyMask = getAnomalyMask(teaching, config);
    if ~any(anomalyMask)
        skipReason = "no anomaly labels found";
        fprintf("Skipping anomaly summary: %s\n", skipReason);
        return;
    end

    anomalyTypes = categorical(teaching.anomaly_type(anomalyMask));
    typeNames = categories(anomalyTypes);
    counts = countcats(anomalyTypes);

    fig = createFigure(config, [120 120 1100 560]);
    ax = axes("Parent", fig);
    bar(ax, categorical(typeNames), counts, "FaceColor", [0.35 0.45 0.75]);
    xlabel(ax, "Anomaly type");
    ylabel(ax, "Point count");
    title(ax, "Tagged anomaly summary");
    applyCommonStyle(ax);
    filePath = saveFigure(fig, config, "08_anomaly_summary.png");
    created = true;
end

% Создает фигуру с едиными параметрами видимости и размера. При figureVisible = "off"
% графики сохраняются в файл без открытия окон MATLAB.
function fig = createFigure(config, positionVector)
    fig = figure("Visible", config.figureVisible, "Color", "w", "Position", positionVector);
end

% Применяет общий стиль осей ко всем обычным графикам: фон, шрифт, сетку,
% толщину линий и рамку. Это делает набор рисунков визуально единым.
function applyCommonStyle(ax)
    ax.Color = [0.97 0.97 0.97];
    ax.FontName = "Arial";
    ax.FontSize = 10;
    ax.LineWidth = 0.8;
    ax.Box = "on";
    ax.XGrid = "on";
    ax.YGrid = "on";
    ax.GridColor = [0.72 0.72 0.72];
    ax.GridAlpha = 0.35;
end

% Сохраняет фигуру в PNG с заданным разрешением и закрывает окно,
% чтобы при массовой генерации не накапливались открытые фигуры.
function filePath = saveFigure(fig, config, fileName)
    filePath = fullfile(config.outputFigureDir, fileName);
    exportgraphics(fig, filePath, "Resolution", config.saveDpi);
    close(fig);
end

% Печатает в консоль краткий отчет о наборе данных и созданных рисунках.
% Эта сводка нужна для быстрой проверки запуска без ручного открытия всех файлов.
function printAnalysisSummary(teaching, groups, createdFigures, config, anomalyDescription, anomalySkipReason)
    residual = teaching.residual_check_mGs;
    finiteResidual = residual(isfinite(residual));
    anomalyMask = getAnomalyMask(teaching, config);

    fprintf("\nTeaching dataset analysis completed.\n");
    fprintf("Rows: %d\n", height(teaching));
    fprintf("Time range: %s to %s\n", string(min(teaching.timestamp_utc)), string(max(teaching.timestamp_utc)));
    fprintf("Segments: %d\n", numel(groups));
    fprintf("Altitude range, km: %.3f to %.3f\n", min(teaching.altitude_km, [], "omitnan"), max(teaching.altitude_km, [], "omitnan"));
    fprintf("B_model_mGs range: %.3f to %.3f\n", min(teaching.B_model_mGs, [], "omitnan"), max(teaching.B_model_mGs, [], "omitnan"));
    fprintf("B_teaching_mGs range: %.3f to %.3f\n", min(teaching.B_teaching_mGs, [], "omitnan"), max(teaching.B_teaching_mGs, [], "omitnan"));
    fprintf("Residual median/MAD/min/max, mGs: %.3f / %.3f / %.3f / %.3f\n", ...
        median(finiteResidual, "omitnan"), median(abs(finiteResidual - median(finiteResidual, "omitnan")), "omitnan"), ...
        min(finiteResidual), max(finiteResidual));
    fprintf("Anomaly points: %d\n", sum(anomalyMask));

    if any(anomalyMask)
        anomalyTypes = categorical(teaching.anomaly_type(anomalyMask));
        typeNames = categories(anomalyTypes);
        counts = countcats(anomalyTypes);
        for k = 1:numel(typeNames)
            fprintf("  %s: %d\n", typeNames{k}, counts(k));
        end
    end

    fprintf("Anomaly description rows: %d\n", height(anomalyDescription));
    fprintf("Generated PNG files: %d\n", numel(createdFigures));
    fprintf("Output directory: %s\n", config.outputFigureDir);
    if strlength(anomalySkipReason) > 0
        fprintf("08_anomaly_summary.png skipped: %s\n", anomalySkipReason);
    end
end

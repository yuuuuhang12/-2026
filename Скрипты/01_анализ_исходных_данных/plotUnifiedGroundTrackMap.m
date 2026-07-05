function fig = plotUnifiedGroundTrackMap(lonDeg, latDeg, colorValue, plotTitle, colorbarLabel, varargin)
%PLOTUNIFIEDGROUNDTRACKMAP Единая функция построения наземного трека спутника.
% Русское название: Унифицированная карта наземного трека.
% При наличии картографических функций используется geoscatter + geobasemap.
% Если подложка недоступна, функция строит обычный график долгота-широта с
% береговой линией MATLAB.

    persistent mapMode

    % Нормализация входных массивов и отбор только конечных значений.
    options = parseOptions(varargin{:});
    lonDeg = normalizeLongitude180(lonDeg(:));
    latDeg = latDeg(:);
    colorValue = colorValue(:);

    validMask = isfinite(lonDeg) & isfinite(latDeg) & isfinite(colorValue);
    if ~any(validMask)
        error("No valid points for ground-track plotting.");
    end

    lonPlot = lonDeg(validMask);
    latPlot = latDeg(validMask);
    colorPlot = colorValue(validMask);
    drawIdx = choosePlotIndices(numel(lonPlot), options.MaxPoints);

    fig = figure("Visible", options.Visible, "Color", "w", "Position", options.Position);

    % Режим карты выбирается один раз и переиспользуется для последующих
    % вызовов, чтобы избежать повторных проверок доступности geobasemap.
    if isempty(mapMode)
        if exist("geoscatter", "file") == 2 && exist("geobasemap", "file") == 2
            mapMode = "geo";
        else
            mapMode = "fallback";
            fprintf("geoscatter/geobasemap unavailable; using lon-lat fallback maps.\n");
        end
    end

    % Основной режим: географическая подложка MATLAB, если она доступна.
    if mapMode == "geo"
        try
            hTrack = geoscatter(latPlot(drawIdx), lonPlot(drawIdx), 28, colorPlot(drawIdx), "filled");
            geobasemap("grayland");
            geolimits([-90 90], [-180 180]);
            setGeoAxisLabels(gca);
            hold on;
            hStart = geoscatter(latPlot(1), lonPlot(1), 55, "g", "filled");
            hEnd = geoscatter(latPlot(end), lonPlot(end), 55, "r", "filled");

            title(plotTitle, "Interpreter", "none");
            addSubtitle(options.SubtitleText);
            cb = colorbar;
            cb.Label.String = colorbarLabel;
            setTurboOrParula();
            legend([hTrack, hStart, hEnd], {"Track points", "Start", "End"}, ...
                "Location", "southoutside", "Orientation", "horizontal");
            return;
        catch ME
            fprintf("geobasemap unavailable: %s\n", ME.message);
            fprintf("Using lon-lat fallback maps for ground tracks.\n");
            mapMode = "fallback";
            clf(fig);
        end
    end

    % Резервный режим: обычные координаты долгота-широта и контур берегов.
    hold on;
    drawCoastlines();
    hTrack = scatter(lonPlot(drawIdx), latPlot(drawIdx), 28, colorPlot(drawIdx), "filled");
    hStart = plot(lonPlot(1), latPlot(1), "go", "MarkerFaceColor", "g", "MarkerSize", 7);
    hEnd = plot(lonPlot(end), latPlot(end), "ro", "MarkerFaceColor", "r", "MarkerSize", 7);

    xlabel("Longitude, deg");
    ylabel("Latitude, deg");
    title(plotTitle, "Interpreter", "none");
    addSubtitle(options.SubtitleText);
    cb = colorbar;
    cb.Label.String = colorbarLabel;
    setTurboOrParula();
    xlim([-180 180]);
    ylim([-90 90]);
    pbaspect([2 1 1]);
    grid on;
    box on;
    legend([hTrack, hStart, hEnd], {"Track points", "Start", "End"}, ...
        "Location", "southoutside", "Orientation", "horizontal");
end

function options = parseOptions(varargin)
    options.Position = [120 120 1100 620];
    options.Visible = "off";
    options.MaxPoints = 50000;
    options.SubtitleText = "";

    if mod(numel(varargin), 2) ~= 0
        error("plotUnifiedGroundTrackMap parameters must be name-value pairs.");
    end

    for k = 1:2:numel(varargin)
        name = char(varargin{k});
        value = varargin{k + 1};
        switch lower(name)
            case "position"
                options.Position = value;
            case "visible"
                options.Visible = value;
            case "maxpoints"
                options.MaxPoints = value;
            case "subtitle"
                options.SubtitleText = value;
            otherwise
                error("Unknown plotUnifiedGroundTrackMap parameter: %s", name);
        end
    end
end

function idx = choosePlotIndices(nPoints, maxPoints)
    if nPoints <= maxPoints
        idx = 1:nPoints;
    else
        idx = unique(round(linspace(1, nPoints, maxPoints)));
    end
end

function drawCoastlines()
    try
        coast = load("coastlines");
        plot(coast.coastlon, coast.coastlat, "Color", [0.65 0.65 0.65], ...
            "LineWidth", 0.6, "HandleVisibility", "off");
    catch
        fprintf("Warning: coastline data unavailable; map background skipped.\n");
    end
end

function lonOut = normalizeLongitude180(lonIn)
    lonOut = mod(lonIn + 180, 360) - 180;
    lonOut(lonOut == -180 & lonIn > 0) = 180;
end

function setTurboOrParula()
    try
        colormap(turbo);
    catch
        colormap(parula);
    end
end

function addSubtitle(subtitleText)
    if strlength(string(subtitleText)) == 0
        return;
    end

    try
        subtitle(subtitleText, "Interpreter", "none");
    catch
        fprintf("Warning: subtitle is unsupported for this axes type.\n");
    end
end

function setGeoAxisLabels(ax)
    try
        ax.LongitudeLabel.String = "Longitude";
        ax.LatitudeLabel.String = "Latitude";
    catch
        % Some MATLAB releases do not expose editable geo-axis labels.
    end
end

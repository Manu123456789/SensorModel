classdef GroupViewer < handle
    % logdb.GroupViewer  Plain-figure 2x2 scatter viewer for the log event database.
    %
    %   v = logdb.GroupViewer(db);
    %   v.launch();                % no groups
    %   v.launch(groups);          % grouped + optional anomaly overlay
    %
    %   groups is an Nx3 or Nx4 cell array:
    %       {EventID, EntityID, GroupLabel}
    %       {EventID, EntityID, GroupLabel, SpecialLabel}
    %
    %   Example:
    %     groups = {
    %         "04_03_10_2024_1_c2", 1, "Batch A", "anomaly";
    %         "04_03_10_2024_1_c2", 2, "Batch B", "anomaly";
    %         "03_02_01_2024_1_a1", 1, "Batch C", "";
    %         "03_02_01_2024_1_a1", 2, "Batch A", "anomaly";
    %     };
    %
    %     v = logdb.GroupViewer(db);
    %     v.launch(groups);
    %
    %   Search for "<-- EDIT" to find configurable lines.
    %   ===== EVENT DROPDOWN: search this phrase for every changed block. =====
    %   Event choices reuse matching (EventID, EntityID/PointID) pairs in groups.
    %   Either dropdown emphasizes its selection and resets the other to All.
    %   Edit localEventLabel below to customize Date / Location / Object text.

    properties (Constant)
        TITLE_1 = "Plot 1 Title"            % <-- EDIT
        TITLE_2 = "Plot 2 Title"            % <-- EDIT
        TITLE_3 = "Plot 3 Title"            % <-- EDIT
        TITLE_4 = "Plot 4 Title"            % <-- EDIT

        XLABEL_1 = "X Label 1"              % <-- EDIT
        XLABEL_2 = "X Label 2"              % <-- EDIT
        XLABEL_3 = "X Label 3"              % <-- EDIT
        XLABEL_4 = "X Label 4"              % <-- EDIT

        YLABEL_1 = "Y Label 1"              % <-- EDIT
        YLABEL_2 = "Y Label 2"              % <-- EDIT
        YLABEL_3 = "Y Label 3"              % <-- EDIT
        YLABEL_4 = "Y Label 4"              % <-- EDIT

        XCOL_1 = "Metric_X"                 % <-- EDIT
        XCOL_2 = "Metric_X"                 % <-- EDIT
        XCOL_3 = "Metric_X"                 % <-- EDIT
        XCOL_4 = "Metric_X"                 % <-- EDIT

        YCOL_1 = "Metric_Y"                 % <-- EDIT
        YCOL_2 = "Metric_Y"                 % <-- EDIT
        YCOL_3 = "Metric_Y"                 % <-- EDIT
        YCOL_4 = "Metric_Y"                 % <-- EDIT

        CIRCLE_1 = [0, 0, 10]               % <-- EDIT [cx, cy, r]
        CIRCLE_3 = [0, 0, 15]               % <-- EDIT [cx, cy, r]
        RECT_2   = [-10, 10, -10, 10]       % <-- EDIT [xmin, xmax, ymin, ymax]
        RECT_4   = [-15, 15, -15, 15]       % <-- EDIT [xmin, xmax, ymin, ymax]

        SHOW_BOUNDS = true                  % <-- EDIT

        % Group palette (intentionally excludes red because red is reserved for anomaly)
        GROUP_COLORS = [ ...                % <-- EDIT
            0.0000 0.4470 0.7410; ...   % blue
            0.4660 0.6740 0.1880; ...   % green
            0.3010 0.7450 0.9330; ...   % cyan
            0.25   0.25   0.25  ...     % dark gray
            ];
    end

    properties (Access = private)
        DB
        Fig
    end

    methods
        function obj = GroupViewer(db)
            arguments
                db logdb.Database
            end
            obj.DB = db;
        end

        function launch(obj, groups)
            pts = obj.DB.getPoints();
            evts = obj.DB.getEvents();

            assert(~isempty(pts) && height(pts) > 0, ...
                'logdb:Viewer:noData', 'PointTable is empty — nothing to plot.');

            % --- Build group label and anomaly mask ---
            groupLabels = repmat("", height(pts), 1);
            anomalyMask = false(height(pts), 1);

            % ===== EVENT DROPDOWN 1: build choices using existing matches =====
            eventItems = {'All Events'};
            pointEventIndex = zeros(height(pts), 1);
            % ===== END EVENT DROPDOWN 1 =====

            if nargin >= 2 && ~isempty(groups) && iscell(groups) && size(groups,2) >= 3
                grpEventsRaw = string(groups(:,1));
                grpLabels    = string(groups(:,3));

                hasSpecialCol = size(groups,2) >= 4;
                if hasSpecialCol
                    specialLabels = strings(size(groups,1),1);
                    for k = 1:size(groups,1)
                        if isempty(groups{k,4})
                            specialLabels(k) = "";
                        else
                            specialLabels(k) = string(groups{k,4});
                        end
                    end
                else
                    specialLabels = repmat("", size(groups,1), 1);
                end

                grpEvents = regexprep(grpEventsRaw, '^log', '', 'ignorecase');

                idCol = "";
                if ismember('EntityID', pts.Properties.VariableNames)
                    idCol = "EntityID";
                elseif ismember('PointID', pts.Properties.VariableNames)
                    idCol = "PointID";
                end

                if idCol == ""
                    warning('logdb:Viewer:noIDColumn', ...
                        ['No EntityID or PointID column found in PointTable. ' ...
                        'Group highlighting is disabled.']);
                else
                    ptEventIDs = string(pts.EventID);
                    ptIDs      = pts.(idCol);

                    matchedAny = false;
                    matchCount = 0;

                    for g = 1:numel(grpEvents)
                        grpID = groups{g,2};

                        if isnumeric(ptIDs)
                            grpIDnum = double(grpID);
                            idMatch = (ptIDs == grpIDnum);
                        else
                            idMatch = string(ptIDs) == string(grpID);
                        end

                        evtMatch = (ptEventIDs == grpEvents(g));
                        match = evtMatch & idMatch;

                        if any(match)
                            % ===== EVENT DROPDOWN 1: one choice per event/object =====
                            if ~any(pointEventIndex(match))
                                eventItems{end+1,1} = localEventLabel(grpEvents(g), grpID);
                                pointEventIndex(match) = numel(eventItems);
                            end
                            % ===== END EVENT DROPDOWN 1 =====
                            groupLabels(match) = grpLabels(g);

                            if strcmpi(strtrim(specialLabels(g)), "anomaly")
                                anomalyMask(match) = true;
                            end

                            matchedAny = true;
                            matchCount = matchCount + nnz(match);
                        end
                    end

                    if ~matchedAny
                        warning('logdb:Viewer:noGroupMatches', ...
                            ['None of the provided group rows matched the PointTable. ' ...
                            'Check EventID formatting and whether your ID column is EntityID or PointID.']);
                    else
                        fprintf('Viewer.launch: matched %d point(s) across %d group row(s).\n', ...
                            matchCount, numel(grpEvents));
                    end
                end
            end

            uniqueGroups = unique(groupLabels(groupLabels ~= ""), 'stable');

            nPalette    = size(obj.GROUP_COLORS, 1);
            groupColors = obj.GROUP_COLORS(mod((1:numel(uniqueGroups))-1, nPalette)+1, :);

            titles  = {obj.TITLE_1,  obj.TITLE_2,  obj.TITLE_3,  obj.TITLE_4};
            xlabels = {obj.XLABEL_1, obj.XLABEL_2, obj.XLABEL_3, obj.XLABEL_4};
            ylabels = {obj.YLABEL_1, obj.YLABEL_2, obj.YLABEL_3, obj.YLABEL_4};
            xCols   = {obj.XCOL_1,   obj.XCOL_2,   obj.XCOL_3,   obj.XCOL_4};
            yCols   = {obj.YCOL_1,   obj.YCOL_2,   obj.YCOL_3,   obj.YCOL_4};
            shapes  = {"circle", "rect", "circle", "rect"};
            bounds  = {[obj.CIRCLE_1, 0], obj.RECT_2, [obj.CIRCLE_3, 0], obj.RECT_4};

            obj.Fig = figure('Name', 'Log Event Viewer', ...
                'Position', [50 50 1400 900], 'Color', 'w');

            % ===== EVENT DROPDOWN 2: both controls are now built in replotAll =====
            plotState.groupItems      = [{'All Groups'}; cellstr(uniqueGroups(:))];
            plotState.eventItems      = eventItems;
            plotState.pointEventIndex = pointEventIndex;
            % ===== END EVENT DROPDOWN 2 =====
            plotState.pts          = pts;
            plotState.evts         = evts;
            plotState.groupLabels  = groupLabels;
            plotState.anomalyMask  = anomalyMask;
            plotState.uniqueGroups = uniqueGroups;
            plotState.groupColors  = groupColors;
            plotState.titles       = titles;
            plotState.xlabels      = xlabels;
            plotState.ylabels      = ylabels;
            plotState.xCols        = xCols;
            plotState.yCols        = yCols;
            plotState.shapes       = shapes;
            plotState.bounds       = bounds;

            setappdata(obj.Fig, 'plotState', plotState);

            replotAll(obj.Fig, 1, 1); % <<< EVENT DROPDOWN 2: start with both All

            dcm = datacursormode(obj.Fig);
            dcm.Enable = 'on';
            dcm.UpdateFcn = @dataCursorFcn;
        end
    end

    methods (Static)
        function v = fromFile(matPath)
            db = logdb.Database();
            db.load(matPath);
            v = logdb.GroupViewer(db);
        end
    end
end

% ===== EVENT DROPDOWN 3: retain choices and rebuild both controls =====
function replotAll(figHandle, groupValue, eventValue)
plotState = getappdata(figHandle, 'plotState');
if isempty(plotState)
    return;
end

items = string(plotState.groupItems);
selectedGroup = items(groupValue);
eventMask = eventValue > 1 & plotState.pointEventIndex == eventValue;

clf(figHandle, 'reset');
setappdata(figHandle, 'plotState', plotState); % Keep state after figure reset.
set(figHandle, 'Name', 'Log Event Viewer', ...
    'Position', [50 50 1400 900], ...
    'Color', 'w');

uicontrol(figHandle, 'Style', 'text', ...
    'String', 'Emphasize:', ...
    'Units', 'normalized', ...
    'Position', [0.01 0.96 0.06 0.03], ...
    'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'right');

newDrop = uicontrol(figHandle, 'Style', 'popupmenu', ...
    'String', cellstr(items), ...
    'Units', 'normalized', ...
    'Position', [0.08 0.96 0.15 0.03], ...
    'Value', groupValue);

uicontrol(figHandle, 'Style', 'text', 'String', 'Event:', ...
    'Units', 'normalized', 'Position', [0.24 0.96 0.04 0.03], ...
    'BackgroundColor', 'w', 'HorizontalAlignment', 'right');
eventDrop = uicontrol(figHandle, 'Style', 'popupmenu', ...
    'String', plotState.eventItems, 'Units', 'normalized', ...
    'Position', [0.29 0.96 0.70 0.03], 'Value', eventValue); % <-- EDIT width here

newDrop.Callback   = @(src,~) replotAll(figHandle, src.Value, 1);
eventDrop.Callback = @(src,~) replotAll(figHandle, 1, src.Value);
% ===== END EVENT DROPDOWN 3 =====

allHandles = [];
allNames   = {};

for p = 1:4
    ax = subplot(2, 2, p, 'Parent', figHandle);

    [h, n] = localPlotScatter(ax, ...
        plotState.pts, plotState.evts, ...
        plotState.groupLabels, plotState.anomalyMask, ...
        selectedGroup, eventMask, plotState.uniqueGroups, plotState.groupColors, ... % <<< EVENT DROPDOWN 4
        plotState.xCols{p}, plotState.yCols{p}, ...
        plotState.titles{p}, plotState.xlabels{p}, plotState.ylabels{p}, ...
        plotState.shapes{p}, plotState.bounds{p});

    % accumulate
    allHandles = [allHandles; h(:)];
    allNames   = [allNames; n(:)];
end

[uniqueNames, ia] = unique(allNames, 'stable');
uniqueHandles = allHandles(ia);

dcm = datacursormode(figHandle);
dcm.Enable = 'on';
dcm.UpdateFcn = @dataCursorFcn;

lgd = legend(uniqueHandles, uniqueNames, ...
    'Orientation', 'horizontal', ...
    'Location', 'southoutside');

lgd.Position(1) = 0.5 - lgd.Position(3)/2;  % center horizontally
lgd.Position(2) = 0.01;                     % pin to bottom
end

function [legendHandles, legendNames] = localPlotScatter(ax, pts, evts, groupLabels, anomalyMask, ...
    emphasizedGroup, eventMask, uniqueGroups, groupColors, ... % <<< EVENT DROPDOWN 4
    xCol, yCol, titleStr, xLabel, yLabel, shape, boundParams)

xData = pts.(xCol);
yData = pts.(yCol);
dist = hypot(xData, yData);
cla(ax);
hold(ax, 'on');

% Calculate bounds independently of how the markers are displayed.
if logdb.GroupViewer.SHOW_BOUNDS
    if shape == "circle"
        cx = boundParams(1); cy = boundParams(2); r = boundParams(3);
        inBox = hypot(xData-cx, yData-cy) <= r;
    else
        inBox = xData >= boundParams(1) & xData <= boundParams(2) & ...
                yData >= boundParams(3) & yData <= boundParams(4);
    end
else
    inBox = true(size(xData));
end

legendHandles = gobjects(0);
legendNames = {};
isAllGroupsMode = emphasizedGroup == "All Groups";
colormap(ax, winter(256));

% ===== EVENT DROPDOWN 4: fade other points; draw selected event/object last =====
if any(eventMask)
    for selected = [false true]
        m = (eventMask == selected);
        c = [0.72 0.72 0.72]; alpha = 0.12; pointSize = 30;
        name = 'Other points';
        if selected
            c = [0 0.4470 0.7410]; alpha = 0.95; pointSize = 46;
            name = 'Selected event';
            k = find(uniqueGroups == groupLabels(find(eventMask, 1)), 1);
            if ~isempty(k), c = groupColors(k,:); end
        end
        mIn = m & inBox;
        mOut = m & ~inBox;
        if any(mIn)
            h = scatter(ax, xData(mIn), yData(mIn), pointSize, c, 'filled', ...
                'MarkerFaceAlpha', alpha, 'MarkerEdgeAlpha', alpha);
            legendHandles(end+1) = h;
            legendNames{end+1} = name;
        end
        if any(mOut)
            h = scatter(ax, xData(mOut), yData(mOut), pointSize+12, c, 'x', ...
                'LineWidth', 1.3, 'MarkerEdgeAlpha', alpha, 'HandleVisibility', 'off');
            if ~any(mIn)
                legendHandles(end+1) = h;
                legendNames{end+1} = name;
            end
        end
    end
elseif isAllGroupsMode
    % ===== END EVENT DROPDOWN 4 =====
    mIn = inBox;
    if any(mIn)
        h = scatter(ax, xData(mIn), yData(mIn), 36, dist(mIn), 'filled', ...
            'MarkerFaceAlpha', 0.80, 'MarkerEdgeAlpha', 0.35);
        legendHandles(end+1) = h;
        legendNames{end+1} = 'Points';
    end

    mOut = ~inBox;
    if any(mOut)
        % Actual OOB points retain their distance-based winter coloring.
        scatter(ax, xData(mOut), yData(mOut), 48, dist(mOut), 'x', ...
            'LineWidth', 1.3, 'HandleVisibility', 'off');
    end

    finiteDist = dist(isfinite(dist));
    if ~isempty(finiteDist)
        caxis(ax, [0 max(max(finiteDist), eps)]); % <<< EVENT DROPDOWN 5: R2021b compatibility
    end
    colorbar(ax);
else
    cb = colorbar(ax);
    cb.Visible = 'off';
    ungroupedMask = groupLabels == "";

    mIn = ungroupedMask & inBox;
    if any(mIn)
        h = scatter(ax, xData(mIn), yData(mIn), 26, [0.72 0.72 0.72], ...
            'filled', 'MarkerFaceAlpha', 0.18, 'MarkerEdgeAlpha', 0.18);
        legendHandles(end+1) = h;
        legendNames{end+1} = 'Ungrouped';
    end

    mOut = ungroupedMask & ~inBox;
    if any(mOut)
        scatter(ax, xData(mOut), yData(mOut), 36, 'x', ...
            'MarkerEdgeColor', [0.60 0.60 0.60], ...
            'LineWidth', 0.9, 'HandleVisibility', 'off');
    end

    for k = 1:numel(uniqueGroups)
        grp = uniqueGroups(k);
        c = groupColors(k,:);
        m = groupLabels == grp;
        if ~any(m), continue; end

        if grp == emphasizedGroup
            faceAlpha = 0.95; edgeAlpha = 0.95;
            sizeIn = 46; sizeOut = 60; lwOut = 1.8;
        else
            faceAlpha = 0.12; edgeAlpha = 0.12;
            sizeIn = 30; sizeOut = 42; lwOut = 0.9;
        end

        mIn = m & inBox;
        mOut = m & ~inBox;
        if any(mIn)
            h = scatter(ax, xData(mIn), yData(mIn), sizeIn, c, 'filled', ...
                'MarkerFaceAlpha', faceAlpha, 'MarkerEdgeAlpha', edgeAlpha);
            legendHandles(end+1) = h;
            legendNames{end+1} = char(grp);
        end
        if any(mOut)
            scatter(ax, xData(mOut), yData(mOut), sizeOut, 'x', ...
                'MarkerEdgeColor', c, 'LineWidth', lwOut, ...
                'HandleVisibility', 'off');
        end
    end
end

% One explicit, consistently visible X symbol for the OOB legend.
if any(~inBox)
    h = scatter(ax, NaN, NaN, 48, 'x', ...
        'MarkerEdgeColor', [0.15 0.15 0.15], 'LineWidth', 1.5);
    legendHandles(end+1) = h;
    legendNames{end+1} = 'Out of bounds';
end

% Draw anomaly rings in two passes because MarkerEdgeAlpha must be scalar.
if any(anomalyMask)
    % ===== EVENT DROPDOWN 4: anomaly rings follow event emphasis =====
    if any(eventMask)
        brightMask = anomalyMask & eventMask;
        fadedMask = anomalyMask & ~eventMask;
    elseif isAllGroupsMode
        % ===== END EVENT DROPDOWN 4 =====
        brightMask = anomalyMask;
        fadedMask = false(size(anomalyMask));
    else
        brightMask = anomalyMask & (groupLabels == emphasizedGroup);
        fadedMask = anomalyMask & ~brightMask;
    end
    if any(fadedMask)
        scatter(ax, xData(fadedMask), yData(fadedMask), 60, 'o', ...
            'MarkerEdgeColor', [0.85 0.10 0.10], ...
            'MarkerFaceColor', 'none', 'LineWidth', 1.2, ...
            'MarkerEdgeAlpha', 0.15, 'HandleVisibility', 'off');
    end
    if any(brightMask)
        scatter(ax, xData(brightMask), yData(brightMask), 60, 'o', ...
            'MarkerEdgeColor', [0.85 0.10 0.10], ...
            'MarkerFaceColor', 'none', 'LineWidth', 1.2, ...
            'MarkerEdgeAlpha', 0.9, 'HandleVisibility', 'off');
    end
    h = scatter(ax, NaN, NaN, 60, 'o', ...
        'MarkerEdgeColor', [0.85 0.10 0.10], ...
        'MarkerFaceColor', 'none', 'LineWidth', 1.2);
    legendHandles(end+1) = h;
    legendNames{end+1} = 'Anomaly';
end

% Draw bounding geometry exactly once; never include it in the legend.
if logdb.GroupViewer.SHOW_BOUNDS
    if shape == "circle"
        theta = linspace(0, 2*pi, 200);
        plot(ax, cx+r*cos(theta), cy+r*sin(theta), '--', ...
            'Color', [0.2 0.7 0.2], 'LineWidth', 1.5, ...
            'HandleVisibility', 'off');
    else
        rectangle(ax, 'Position', ...
            [boundParams(1), boundParams(3), ...
             boundParams(2)-boundParams(1), boundParams(4)-boundParams(3)], ...
            'EdgeColor', [0.2 0.7 0.2], 'LineWidth', 1.5, ...
            'LineStyle', '--', 'HandleVisibility', 'off');
    end
end

xlabel(ax, xLabel, 'Interpreter', 'none');
ylabel(ax, yLabel, 'Interpreter', 'none');
title(ax, titleStr, 'Interpreter', 'none');
grid(ax, 'on');

ax.UserData.pts = pts;
ax.UserData.evts = evts;
ax.UserData.xCol = char(xCol);
ax.UserData.yCol = char(yCol);
ax.UserData.groupLabels = groupLabels;
ax.UserData.anomalyMask = anomalyMask;
hold(ax, 'off');

[~, ia] = unique(legendNames, 'stable');
legendHandles = legendHandles(ia);
legendNames = legendNames(ia);
end

% ===== EVENT DROPDOWN 6: EDIT THE DISPLAY FORMAT HERE =====
function label = localEventLabel(eventID, objectID)
id = char(eventID);
% Extract the two-number/year date, wherever it occurs; preserve its order.
dateText = regexp(id, '(?<!\d)\d{1,2}_\d{1,2}_\d{4}(?!\d)', 'match', 'once'); % <-- EDIT date pattern
% A standalone letter + digits (T2, c2, a1, etc.), anywhere in the EventID.
location = regexp(id, '(?<![A-Za-z0-9])[A-Za-z]\d+(?![A-Za-z0-9])', 'match', 'once'); % <-- EDIT location pattern
if isempty(dateText), dateText = '?'; end
if isempty(location), location = '?'; end
dateText = strrep(dateText, '_', '/'); % <-- EDIT date separator
label = sprintf('Date: %s | Location: %s | Object: %s', ... % <-- EDIT OUTPUT FORMAT
    dateText, upper(location), char(string(objectID)));
end
% ===== END EVENT DROPDOWN 6 =====

function txt = dataCursorFcn(~, event)
ax  = get(event.Target, 'Parent');
ud  = ax.UserData;
pos = event.Position;

pts  = ud.pts;
evts = ud.evts;
xCol = ud.xCol;
yCol = ud.yCol;

xData = pts.(xCol);
yData = pts.(yCol);

d = (xData - pos(1)).^2 + (yData - pos(2)).^2;
[~, idx] = min(d);

eid     = char(string(pts.EventID(idx)));
eidDisp = strrep(eid, '_', '\_');
xDisp   = strrep(xCol, '_', '\_');
yDisp   = strrep(yCol, '_', '\_');

txt = { ...
    sprintf('EventID: %s', eidDisp), ...
    sprintf('%s: %.4g', xDisp, xData(idx)), ...
    sprintf('%s: %.4g', yDisp, yData(idx))};

evtIdx = find(string(evts.EventID) == string(eid), 1);
if ~isempty(evtIdx)
    if ismember('Date', evts.Properties.VariableNames)
        txt{end+1} = sprintf('Date: %s', char(string(evts.Date(evtIdx))));
    end
    if ismember('LogNumber', evts.Properties.VariableNames)
        txt{end+1} = sprintf('Log#: %d', evts.LogNumber(evtIdx));
    end
    if ismember('RunNumber', evts.Properties.VariableNames)
        txt{end+1} = sprintf('Run#: %d', evts.RunNumber(evtIdx));
    end
    if ismember('Site', evts.Properties.VariableNames)
        txt{end+1} = sprintf('Site: %s', char(string(evts.Site(evtIdx))));
    end
end

ptCols = pts.Properties.VariableNames;

if ismember('EntityID', ptCols)
    entVal = pts.EntityID(idx);
    if isnumeric(entVal)
        txt{end+1} = sprintf('EntityID: %d', entVal);
    else
        txt{end+1} = sprintf('EntityID: %s', char(string(entVal)));
    end
elseif ismember('PointID', ptCols)
    ptVal = pts.PointID(idx);
    if isnumeric(ptVal)
        txt{end+1} = sprintf('PointID: %d', ptVal);
    else
        txt{end+1} = sprintf('PointID: %s', char(string(ptVal)));
    end
end

if isfield(ud, 'groupLabels')
    grp = string(ud.groupLabels(idx));
    if strlength(grp) == 0
        txt{end+1} = 'Group: Ungrouped';
    else
        txt{end+1} = sprintf('Group: %s', char(grp));
    end
end

if isfield(ud, 'anomalyMask')
    txt{end+1} = sprintf('Anomaly: %s', string(ud.anomalyMask(idx)));
end

if ismember('Flag', ptCols)
    txt{end+1} = sprintf('Flag: %s', char(string(pts.Flag(idx))));
end
end

Background:
First, capture the original number when loading succeeds. Adapt this example to your existing loader:
Runs = {}; runID = [];
for attempt = 1:100
    try
        a = load(sprintf('run_%03d.mat',attempt)); s = a.run; % Adapt
        assert(isstruct(s) && isscalar(s),'Expected one run struct.');
    catch
        continue
    end
    Runs{end+1} = s; runID(end+1) = attempt;
end

If your loader already appends the struct, add only the corresponding runID assignment there. Previously discarded run IDs cannot be recovered from the packed cells alone.
Use these derived names in fields, matchFields, and ref:
Name	ECEF output	ACD output
v1	X velocity	Altitude velocity
v2	Y velocity	Crossrange velocity
v3	Z velocity	Downrange velocity
speed	Velocity magnitude	Velocity magnitude


Other quantities use their actual struct field names. Signals must be numeric vectors matching their run’s time vector.
Run this after loading:
%% SETTINGS
fields = {'v1','v2','v3','positionX','positionY','positionZ'}; % Add 'fuelUse','speed',etc.
out = fullfile(pwd,'MCplots'); tf = 'time';
vf = {'velocityX','velocityY','velocityZ'}; % Actual source velocity field names
showLines = false; doMatch = false; opacity = 0.12;
sourceFrame = 'ECEF'; frame = 'ECEF'; % Output: 'ECEF' or 'ACD'
C = []; % ECEF->ACD rotation: rows = A,C,D unit axes expressed in ECEF.
ref = struct; % ref.FIELD = [time value]; overlays also work with doMatch=false.
% ref.fuelUse = [20 12;30 18;50 31;70 43]; % EXAMPLE: replace with measurements.
% ref.speed = [22 140;46 155;68 163];      % Independent reference times
matchFields = {'fuelUse','speed'}; scale = [1 10]; % Error scale per quantity

%% PREPARE
assert(numel(Runs)==numel(runID),'Store one original runID for every cell.');
keep = ~cellfun(@isempty,Runs); R = Runs(keep); id = runID(keep); n = numel(R);
assert(n>0,'No loaded runs.'); frame = upper(frame);
assert(any(strcmp(frame,{'ECEF','ACD'})),'Frame must be ECEF or ACD.');
aliases = {'v1','v2','v3','speed'};
needV = any(ismember(fields,aliases)) || (doMatch && any(ismember(matchFields,aliases)));
for k = 1:n
    s = R{k}; t = s.(tf); t = t(:);
    assert(numel(t)>1 && all(isfinite(t)) && all(diff(t)>0),'Time must increase and be finite.');
    if needV
        V = zeros(numel(t),3); for j=1:3, v=s.(vf{j}); V(:,j)=v(:); end
        % ===== EDIT VELOCITY CONVERSION: V is N-by-3; s,t are available =====
        if ~strcmpi(sourceFrame,'ECEF')
            error('Replace this error with your source-to-ECEF velocity conversion.');
            % Set V to Earth-relative ECEF velocity using time/epoch and position.
            % For inertial derivatives, include the Earth-rotation transport term.
        end
        if strcmp(frame,'ACD')
            % Define C here using your origin/heading/reference data if needed.
            % For time-varying axes, replace these two lines with per-sample rotations.
            assert(isequal(size(C),[3 3]),'Supply C or edit the ACD conversion block.');
            V = V*C.';
        end
        % ===== END VELOCITY CONVERSION =====
        for j = 1:3, s.(aliases{j}) = V(:,j); end
        s.speed = sqrt(sum(V.^2,2)); R{k} = s;
    end
end
labels = {'ECEF velocity X','ECEF velocity Y','ECEF velocity Z','Velocity magnitude'};
if strcmp(frame,'ACD'), labels(1:3) = {'Altitude velocity','Crossrange velocity','Downrange velocity'}; end

%% PLOT: always patches; optionally an additional line figure per quantity.
if ~exist(out,'dir'), mkdir(out); end
G = gobjects(size(fields)); modes = {'patch','lines'};
for j = 1:numel(fields)
    f = fields{j}; label = f; a = find(strcmp(f,aliases));
    if ~isempty(a), label = labels{a}; end
    for m = 0:showLines
        fig = figure('Color','w','Renderer','opengl','Name',[label ' - ' modes{m+1}]);
        ax = axes('Parent',fig); hold(ax,'on');
        if m==0, G(j) = hggroup('Parent',ax,'Tag','MCGroup'); end
        for k = 1:n
            s = R{k}; t = s.(tf); y = s.(f); t = t(:); y = y(:);
            if m==0
                patch('Parent',G(j),'XData',[t;NaN],'YData',[y;NaN],...
                    'FaceColor','none','EdgeColor',[.3 .3 .3],'EdgeAlpha',opacity,'HitTest','off');
            else
                h = plot(ax,t,y,'Color',[.65 .65 .65]);
                h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow('Original run',id(k)*ones(size(t)),'%d');
            end
        end
        if isfield(ref,f), q = ref.(f); plot(ax,q(:,1),q(:,2),'ro','MarkerFaceColor','r'); end
        grid(ax,'on'); xlabel(ax,'Time (s)'); ylabel(ax,label,'Interpreter','none');
        title(ax,[label ' - ' modes{m+1}],'Interpreter','none');
        if m==1, datacursormode(fig,'on'); end
        file = fullfile(out,[f '_' frame '_' modes{m+1}]);
        savefig(fig,[file '.fig']); exportgraphics(ax,[file '.png'],'Resolution',150);
    end
end

%% MATCH: sum of per-quantity mean squared errors, normalized by scale.
bestRun = []; results = [];
if doMatch
    assert(~isempty(matchFields) && numel(scale)==numel(matchFields) && all(isfinite(scale) & scale>0),...
        'Provide one positive, finite scale per matching quantity.');
    score = zeros(n,1);
    for j = 1:numel(matchFields)
        f = matchFields{j}; q = ref.(f);
        assert(~isempty(q) && size(q,2)==2 && all(isfinite(q(:))),'Reference must be finite [time value] rows.');
        for k = 1:n
            s = R{k}; t = s.(tf); y = s.(f); t = t(:); y = y(:);
            e = (interp1(t,y,q(:,1),'linear',NaN)-q(:,2))/scale(j);
            if any(~isfinite(e)), score(k)=Inf; else, score(k)=score(k)+mean(e.^2); end
        end
    end
    results = sortrows(table(id(:),score,'VariableNames',{'OriginalRun','Score'}),'Score');
    if isfinite(results.Score(1))
        bestRun = results.OriginalRun(1); fprintf('Best original run: %g (score %g)\n',bestRun,results.Score(1));
    else, warning('No run has finite predictions at every required reference time.'); end
end

A few usage details:
- Plots: Default settings produce six grouped-patch figures. showLines=true adds six selectable-line figures with original-run data tips. Every figure saves as .fig and .png; reference measurements appear as red dots.
- Matching: Supply the reference pairs and set doMatch=true. For fuel alone, use matchFields={'fuelUse'}; scale=1;. For combined matching, [1 10] makes a 1-unit fuel error contribute like a 10-unit speed error. Each quantity is averaged separately, so more samples do not automatically give it more weight.
- Results: bestRun contains the original run number; results contains the ranking. Runs missing coverage at any required reference time receive Inf; no extrapolation is used.
- Coordinates: ACD requires your rotation C or your replacement conversion logic. Reference values must use the same units, time origin, and frame as the quantities being compared.
G(j) contains the entire Monte Carlo patch group for fields{j}. With the desired axes active in your destination .fig, copy it as one unit using: MATLAB
copyobj(G(1),gca);

The data-tip and export APIs were introduced before R2021b. I checked the matching math with synthetic cases, but could not execute MATLAB graphics here

%%%%%%%%%%%%%%%

%% SETTINGS: Runs{k} = scalar run struct; runID(k) = original loading counter.
fields = {'v1','v2','v3','positionX','positionY','positionZ'}; % Add 'fuelUse','speed',etc.
out = fullfile(pwd,'MCplots'); tf = 'time';
vf = {'velocityX','velocityY','velocityZ'}; % Actual source velocity field names
showLines = false; doMatch = false; opacity = 0.12;
sourceFrame = 'ECEF'; frame = 'ECEF'; % Output frame: 'ECEF' or 'ACD'
C = []; % Fixed ECEF->ACD rotation: rows are A,C,D unit axes expressed in ECEF.
ref = struct; % Each ref.FIELD = [time value]; used for overlays even if doMatch=false.
% ref.fuelUse = [20 12;30 18;50 31;70 43]; % EXAMPLE ONLY: replace with measurements.
% ref.speed = [22 140;46 155;68 163];      % Independent reference times are allowed.
matchFields = {'fuelUse','speed'}; scale = [1 10]; % Positive error scale per quantity

%% PREPARE: v1/v2/v3 and speed are derived aliases in a working copy.
assert(numel(Runs)==numel(runID),'Store one original runID for every cell.');
keep = ~cellfun(@isempty,Runs); R = Runs(keep); id = runID(keep); n = numel(R);
assert(n>0,'No loaded runs.'); frame = upper(frame);
assert(any(strcmp(frame,{'ECEF','ACD'})),'Frame must be ECEF or ACD.');
aliases = {'v1','v2','v3','speed'};
needV = any(ismember(fields,aliases)) || (doMatch && any(ismember(matchFields,aliases)));
for k = 1:n
    s = R{k}; t = s.(tf); t = t(:);
    assert(numel(t)>1 && all(isfinite(t)) && all(diff(t)>0),'Time must increase and be finite.');
    if needV
        V = zeros(numel(t),3); for j=1:3, v=s.(vf{j}); V(:,j)=v(:); end
        % ===== EDIT VELOCITY CONVERSION: V is N-by-3; s,t are available =====
        if ~strcmpi(sourceFrame,'ECEF')
            error('Replace this error with your source-to-ECEF velocity conversion.');
            % Set V to Earth-relative ECEF velocity using time/epoch and position.
            % For inertial derivatives, include the Earth-rotation transport term.
        end
        if strcmp(frame,'ACD')
            % Define C here using your origin/heading/reference data if needed.
            % For time-varying axes, replace these two lines with per-sample rotations.
            assert(isequal(size(C),[3 3]),'Supply C or edit the ACD conversion block.');
            V = V*C.';
        end
        % ===== END VELOCITY CONVERSION =====
        for j = 1:3, s.(aliases{j}) = V(:,j); end
        s.speed = sqrt(sum(V.^2,2)); R{k} = s;
    end
end
labels = {'ECEF velocity X','ECEF velocity Y','ECEF velocity Z','Velocity magnitude'};
if strcmp(frame,'ACD'), labels(1:3) = {'Altitude velocity','Crossrange velocity','Downrange velocity'}; end

%% PLOT: always patches; optionally an additional line figure per quantity.
if ~exist(out,'dir'), mkdir(out); end
G = gobjects(size(fields)); modes = {'patch','lines'};
for j = 1:numel(fields)
    f = fields{j}; label = f; a = find(strcmp(f,aliases));
    if ~isempty(a), label = labels{a}; end
    for m = 0:showLines
        fig = figure('Color','w','Renderer','opengl','Name',[label ' - ' modes{m+1}]);
        ax = axes('Parent',fig); hold(ax,'on');
        if m==0, G(j) = hggroup('Parent',ax,'Tag','MCGroup'); end
        for k = 1:n
            s = R{k}; t = s.(tf); y = s.(f); t = t(:); y = y(:);
            if m==0
                patch('Parent',G(j),'XData',[t;NaN],'YData',[y;NaN],...
                    'FaceColor','none','EdgeColor',[.3 .3 .3],'EdgeAlpha',opacity,'HitTest','off');
            else
                h = plot(ax,t,y,'Color',[.65 .65 .65]);
                h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow('Original run',id(k)*ones(size(t)),'%d');
            end
        end
        if isfield(ref,f), q = ref.(f); plot(ax,q(:,1),q(:,2),'ro','MarkerFaceColor','r'); end
        grid(ax,'on'); xlabel(ax,'Time (s)'); ylabel(ax,label,'Interpreter','none');
        title(ax,[label ' - ' modes{m+1}],'Interpreter','none');
        if m==1, datacursormode(fig,'on'); end
        file = fullfile(out,[f '_' frame '_' modes{m+1}]);
        savefig(fig,[file '.fig']); exportgraphics(ax,[file '.png'],'Resolution',150);
    end
end

%% MATCH: sum of per-quantity mean squared errors, normalized by scale.
bestRun = []; results = [];
if doMatch
    assert(~isempty(matchFields) && numel(scale)==numel(matchFields) && all(isfinite(scale) & scale>0),...
        'Provide one positive, finite scale per matching quantity.');
    score = zeros(n,1);
    for j = 1:numel(matchFields)
        f = matchFields{j}; q = ref.(f);
        assert(~isempty(q) && size(q,2)==2 && all(isfinite(q(:))),'Reference must be finite [time value] rows.');
        for k = 1:n
            s = R{k}; t = s.(tf); y = s.(f); t = t(:); y = y(:);
            e = (interp1(t,y,q(:,1),'linear',NaN)-q(:,2))/scale(j);
            if any(~isfinite(e)), score(k)=Inf; else, score(k)=score(k)+mean(e.^2); end
        end
    end
    results = sortrows(table(id(:),score,'VariableNames',{'OriginalRun','Score'}),'Score');
    if isfinite(results.Score(1))
        bestRun = results.OriginalRun(1); fprintf('Best original run: %g (score %g)\n',bestRun,results.Score(1));
    else, warning('No run has finite predictions at every required reference time.'); end
end

% LOADING EXAMPLE (adapt filename and MAT-file variable name):
% Runs = {}; runID = [];
% for attempt = 1:100
%     try
%         a = load(sprintf('run_%03d.mat',attempt)); s = a.run;
%         assert(isstruct(s) && isscalar(s),'Expected one run struct.');
%     catch
%         continue
%     end
%     Runs{end+1} = s; runID(end+1) = attempt;
% end
% To copy the j-th patch group into an existing destination axes:
% copyobj(G(j),destinationAxes);

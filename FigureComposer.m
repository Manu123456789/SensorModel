%% FIGURE COMPOSER - MATLAB R2021b, based on YOUR pasted script.
% [CHANGE 1 BEGIN] Replace the original setup above the Implementation section.
% First test: run RUN_DEMO. It creates all example .fig files automatically.
% For your own figures: change ONLY the paths, filenames and mappings below.
packageDir = fileparts(mfilename('fullpath'));
baseDir = fullfile(packageDir,'demo_base');
source = fullfile(packageDir,'demo_source');
output = fullfile(packageDir,'demo_output');

% For real data, replace the three folder assignments, for example:
% baseDir='C:\Results\Nominal'; source='C:\Results\MonteCarlo';
% output='C:\Results\Combined';
o=struct();
o.FileMap={}; o.AxesMap={};
o.AxesBy='Tile';                    % NEW: actual tiledlayout anchor numbers.
% For ordinary subplot() figures use 'Title' or 'Tag' and matching text keys.
% Tile numbers are local to a layout; repeated numbers across multiple layouts
% require unique titles/tags. No reliance on the order returned by findall.
o.SelectBy='Tag';
o.Include={}; o.Exclude={};         % Copy all supported plot objects.
% Optional: o.Include={'MonteCarlo'}; (the source graphics must have that Tag).
% Alternatively: o.SelectBy='DisplayName'; o.Include={'Modified Y'};
o.Style=struct('DisplayName','Monte Carlo'); % One MC legend entry per axes.
% Use struct() to retain source names. Other supported style overrides:
% o.Style.LineWidth=1.5; o.Style.LineStyle='--';
% o.Style.EdgeAlpha=0.12;            % Patch-edge transparency only.
% o.Style.FaceAlpha=0.12;            % Filled-patch transparency only.
o.Layer='bottom';                  % Keep nominal curves above the MC cloud.
o.Limits='base';                   % 'auto' expands limits to include all data.
o.Legend='update';                 % 'keep' preserves the base legend entries.
% [CHANGE 7A NEW] Enable PNG output alongside each .fig.
o.Overwrite=true; o.PNG=true;

% Each row: {SOURCE FIGURE, SOURCE AXES KEY, DESTINATION AXES KEY}.
% '' selects the only axes in a figure, regardless of title/tag/layout.
% The source and destination titles/labels DO NOT have to match.
% VELOCITY: 3-by-2, row-major layout. Right-hand axes spans [3 1], starts at 2.
o.SourceMap={
    fullfile(source,'VelocityX.fig'),   '', 1
    fullfile(source,'VelocityY.fig'),   '', 3
    fullfile(source,'VelocityZ.fig'),   '', 5
    fullfile(source,'VelocityRSS.fig'), '', 2
};
composeFigures(source,fullfile(baseDir,'Velocity.fig'),output,o);

% TRAJECTORY: three vertical tiles, top-to-bottom.
o.SourceMap={
    fullfile(source,'TrajectoryX.fig'), '', 1
    fullfile(source,'TrajectoryY.fig'), '', 2
    fullfile(source,'TrajectoryZ.fig'), '', 3
};
composeFigures(source,fullfile(baseDir,'Trajectory.fig'),output,o);

% FUEL: a single ordinary axes, not even a tiledlayout.
o.SourceMap={fullfile(source,'Fuel.fig'), '', ''};
composeFigures(source,fullfile(baseDir,'Fuel.fig'),output,o);

% Remove an entire job block to skip that figure. Output uses each base name.
% Add rows with the same destination key to overlay more datasets on a tile.
% Optional FOURTH column: row overrides (all rows then need four entries).
% Use struct() to inherit defaults; allowed fields: SelectBy, Include,
% Exclude, Style, Layer. Example row override:
% struct('Style',struct('DisplayName','Case B','LineWidth',1.5))
% Style replaces the global Style struct for that row.
%
% Legacy pair/directory mode: replace all job blocks above with:
% o.SourceMap={}; o.AxesBy='Tag';
% composeFigures(source,baseDir,output,o);
% Optional FileMap={'SourceName.fig','BaseName.fig'};
% Optional AxesMap={'SourceTag','DestinationTag'};
%
% Scope: Cartesian axes, lines/patches/scatter/common charts and groups.
% Select groups by their root Tag/DisplayName. No raw-data transformation.
% Same units, frame and time reference are required. No yyaxis/polar/geoaxes.
% Saved figures are invisible: use openfig(filename,'visible') to view them.
% [CHANGE 1 END]

%% Implementation - no edits normally needed below this line.
function composeFigures(source,base,output,o)
    o=normalizeOptions(o);
    assert(isempty(o.FileMap) || size(o.FileMap,2)==2,'FileMap needs two columns.');
    assert(isempty(o.AxesMap) || size(o.AxesMap,2)==2,'AxesMap needs two columns.');
    mapped=~isempty(o.SourceMap);
    if mapped
        assert(iscell(o.SourceMap) && ismember(size(o.SourceMap,2),[3 4]), ...
            'SourceMap must be a cell array with 3 or 4 columns.');
        assert(isfile(base),'SourceMap mode needs one existing base .fig file.');
        assert(isempty(o.FileMap) && isempty(o.AxesMap),'Clear FileMap/AxesMap when using SourceMap.');
        sources=string(o.SourceMap(:,1)); bases=string(base);
    elseif isfolder(source) && isfolder(base)
        pairs = string(o.FileMap);
        if isempty(pairs)
            s = dir(fullfile(source,'*.fig')); b = dir(fullfile(base,'*.fig'));
            names = intersect(string({s.name}),string({b.name}));
            pairs = [names(:),names(:)];
            if numel(names)<numel(s) || numel(names)<numel(b)
                warning('Composer:Unpaired','Only common .fig filenames will be combined.');
            end
        end
        sources = fullfile(string(source),pairs(:,1));
        bases = fullfile(string(base),pairs(:,2));
    else
        assert(isfile(source) && isfile(base),'Inputs must be two directories or two .fig files.');
        assert(isempty(o.FileMap),'FileMap is only used with directories.');
        sources = string(source); bases = string(base);
    end
    assert(~isempty(sources),'No matching figures. Check paths or FileMap.');
    if ~isfolder(output), mkdir(output); end
    [ok,info] = fileattrib(output); assert(ok,'Cannot access output directory.');
    for k=1:numel(sources)
        [ok,a] = fileattrib(sources(k)); assert(ok,'Missing source: %s',sources(k));
        sources(k)=string(a.Name);
        [~,~,ext]=fileparts(sources(k));
        assert(strcmpi(ext,'.fig'),'Source must be a .fig file: %s',sources(k));
    end
    outputs = strings(size(bases));
    for k=1:numel(bases)
        [ok,a] = fileattrib(bases(k)); assert(ok,'Missing base: %s',bases(k));
        bases(k) = string(a.Name);
        [~,name,ext] = fileparts(bases(k));
        assert(strcmpi(ext,'.fig'),'Base must be a .fig file: %s',bases(k));
        outputs(k) = fullfile(string(info.Name),name+ext);
    end
    if mapped, o.SourceMap(:,1)=cellstr(sources); end
    inputs = [sources;bases]; checkOutputs = outputs;
    if ispc, inputs=lower(inputs); checkOutputs=lower(checkOutputs); end
    assert(~any(ismember(checkOutputs,inputs)),'Output must not overwrite ANY source/base figure.');
    assert(numel(unique(checkOutputs))==numel(outputs),'FileMap has duplicate output filenames.');
    % Include HandleVisibility='off' MC objects; restore root setting on exit.
    hidden = get(groot,'ShowHiddenHandles');
    restore = onCleanup(@()set(groot,'ShowHiddenHandles',hidden)); %#ok<NASGU>
    set(groot,'ShowHiddenHandles','on');
    saved = 0;
    for k=1:numel(bases)
        try
            assert(o.Overwrite || ~isfile(outputs(k)),'Output exists: %s',outputs(k));
            if mapped, n=composeMapped(bases(k),outputs(k),o);
            else, n=composeOne(sources(k),bases(k),outputs(k),o); end
            fprintf('Saved %s (%d objects copied)\n',outputs(k),n);
            saved = saved+1;
        catch ME
            % [CHANGE 2] Stop at the actual error; do not hide it behind 0/1 saved.
            rethrow(ME);
        end
    end
    fprintf('Completed: %d/%d figures saved.\n',saved,numel(bases));
end

function count = composeMapped(base,output,o)
    b=openfig(base,'new','invisible');
    cleanB=onCleanup(@()delete(b)); %#ok<NASGU>
    assert(isscalar(b),'Each .fig must contain one figure.');
    axesList=findall(b,'Type','axes');
    assert(~isempty(axesList),'No Cartesian axes in base figure.');
    % Preserve base-first legend order even when several sources share a tile.
    entries=cell(size(axesList)); changed=false(size(axesList)); count=0;
    for j=1:numel(axesList), entries{j}=flipud(axesList(j).Children); end
    for r=1:size(o.SourceMap,1)
        try
            [copied,ax]=copyMappedRow(o.SourceMap(r,:),axesList,o);
            j=find(axesList==ax); entries{j}=[entries{j};copied]; changed(j)=true;
            count=count+numel(copied);
        catch ME
            error('Composer:SourceMap','SourceMap row %d (%s): %s',r,string(o.SourceMap{r,1}),ME.message);
        end
    end
    if strcmp(o.Legend,'update')
        for j=find(changed(:))', updateLegend(axesList(j),entries{j}); end
    end
    % A failed row aborts this figure before saving a partial composition.
    saveOutput(b,output,o);
end

function [copied,ax] = copyMappedRow(row,axesList,o)
    if numel(row)==4
        extra=row{4}; assert(isstruct(extra) && isscalar(extra),'Row overrides must be a scalar struct.');
        fields=fieldnames(extra);
        allowed={'SelectBy','Include','Exclude','Style','Layer'};
        assert(all(ismember(fields,allowed)),'Unsupported row override. See SourceMap comments.');
        for i=1:numel(fields), o.(fields{i})=extra.(fields{i}); end
        o=normalizeOptions(o);
    end
    s=openfig(row{1},'new','invisible');
    cleanS=onCleanup(@()delete(s)); %#ok<NASGU>
    assert(isscalar(s),'Each source .fig must contain one figure.');
    from=uniqueAxis(findall(s,'Type','axes'),string(row{2}),o.AxesBy);
    ax=uniqueAxis(axesList,string(row{3}),o.AxesBy);
    o.Legend='keep'; % Build each destination legend once, after all rows.
    copied=copyPlotObjects(from,ax,o);
end

function count = composeOne(source,base,output,o)
    s = openfig(source,'new','invisible');
    cleanS = onCleanup(@()delete(s)); %#ok<NASGU>
    b = openfig(base,'new','invisible');
    cleanB = onCleanup(@()delete(b)); %#ok<NASGU>
    assert(isscalar(s) && isscalar(b),'Each .fig must contain one figure.');
    sa = findall(s,'Type','axes'); ba = findall(b,'Type','axes');
    assert(~isempty(sa) && ~isempty(ba),'No Cartesian axes found.');
    if isempty(o.AxesMap)
        from = sa; to = gobjects(size(sa));
        for j=1:numel(sa)
            if isempty(selected(sa(j),o)), continue; end
            if numel(sa)==1 && numel(ba)==1
                to(j)=ba;
            else
                key = axesKey(sa(j),o.AxesBy);
                uniqueAxis(sa,key,o.AxesBy); % Also reject duplicate source keys.
                to(j)=uniqueAxis(ba,key,o.AxesBy);
            end
        end
    else
        map = string(o.AxesMap); from = gobjects(size(map,1),1); to = from;
        assert(numel(unique(map(:,1)))==size(map,1) && ...
            numel(unique(map(:,2)))==size(map,1),'AxesMap must be one-to-one.');
        for j=1:size(map,1)
            from(j)=uniqueAxis(sa,map(j,1),o.AxesBy);
            to(j)=uniqueAxis(ba,map(j,2),o.AxesBy);
        end
    end
    count = 0;
    for j=1:numel(from)
        if isempty(selected(from(j),o)), continue; end
        copied=copyPlotObjects(from(j),to(j),o);
        count = count+numel(copied);
    end
    assert(count>0,'No objects selected. Check Include/Exclude and object identifiers.');
    saveOutput(b,output,o);
end

function copied = copyPlotObjects(from,ax,o)
    objects=selected(from,o);
    assert(~isempty(objects),'No objects selected. Check Include/Exclude and identifiers.');
    assert(numel(from.YAxis)==1 && numel(ax.YAxis)==1,'yyaxis is not supported.');
    limits={ax.XLim,ax.YLim,ax.ZLim}; old=ax.Children;
    if ~isempty(ax.Legend), ax.Legend.AutoUpdate='off'; end
    copied=gobjects(numel(objects),1);
    % Bottom-to-top source order; copying never clears existing graphics.
    for i=1:numel(objects)
        copied(i)=copyobj(objects(i),ax); styleObjects(copied(i),o.Style);
    end
    if strcmp(o.Layer,'bottom'), ax.Children=[old;flipud(copied)];
    else, ax.Children=[flipud(copied);old]; end
    if isequal(ax.View,[0 90]), ax.SortMethod='childorder'; end
    if strcmp(o.Legend,'update'), updateLegend(ax,[flipud(old);copied]); end
    if strcmp(o.Limits,'base')
        set(ax,'XLim',limits{1},'YLim',limits{2},'ZLim',limits{3});
    else
        set(ax,'XLimMode','auto','YLimMode','auto','ZLimMode','auto');
    end
end

function saveOutput(fig,output,o)
    % [CHANGE 7B NEW BEGIN] Fit each Y axis to all plotted data before saving.
    % Comment out this line to retain base Y limits; 'padded' adds a margin.
    set(findall(fig,'Type','axes'),'YLimMode','auto','YLimitMethod','tight');
    % [CHANGE 7B NEW END] X/Z limits stay as configured; applies to FIG and PNG.
    savefig(fig,output);
    if o.PNG
        [folder,name] = fileparts(output);
        png=fullfile(folder,name+".png");
        try
            assert(o.Overwrite || ~isfile(png),'PNG output already exists.');
            % [CHANGE 3 BEGIN] Whole-figure PNG path for MATLAB R2021b.
            set(fig,'PaperPositionMode','auto');
            print(fig,char(png),'-dpng','-r200');
            % [CHANGE 3 END]
        catch ME
            warning('Composer:PNG','FIG saved, but PNG export failed: %s',ME.message);
        end
    end
end

% [CHANGE 4 BEGIN] Replace the entire original axesKey function.
function key = axesKey(ax,by)
    switch by
        case 'Tag'
            key=string(ax.Tag);
        case 'Title'
            key=strjoin(string(ax.Title.String)," ");
        case 'Tile'
            key="";
            if isa(ax.Parent,'matlab.graphics.layout.TiledChartLayout')
                key=string(ax.Layout.Tile);
            end
    end
end
% [CHANGE 4 END]

function ax = uniqueAxis(axesList,key,by)
    if strlength(key)==0
        assert(numel(axesList)==1,'Blank axes key requires exactly one Cartesian axes (%d found).',numel(axesList));
        ax=axesList; return;
    end
    matches = arrayfun(@(a)strcmp(axesKey(a,by),key),axesList);
    assert(nnz(matches)==1,'Axes key "%s" must match exactly once (%d matches).',key,nnz(matches));
    ax = axesList(matches);
end

function o = normalizeOptions(o)
    % [CHANGE 5] Tile must be accepted here as well as implemented in axesKey.
    o.AxesBy=validatestring(o.AxesBy,{'Tag','Title','Tile'});
    o.SelectBy=validatestring(o.SelectBy,{'Tag','DisplayName'});
    o.Layer=validatestring(o.Layer,{'top','bottom'});
    o.Limits=validatestring(o.Limits,{'base','auto'});
    o.Legend=validatestring(o.Legend,{'keep','update'});
    assert(isstruct(o.Style) && isscalar(o.Style),'Style must be a scalar struct.');
end

function objects = selected(ax,o)
    objects = flipud(ax.Children); keep = false(size(objects));
    % Excludes axes titles/labels, text annotations, legends and colorbars.
    types = {'line','patch','scatter','surface','bar','area','errorbar', ...
        'histogram','stair','stem','quiver','contour','image','hggroup','hgtransform','constantline'};
    for i=1:numel(objects)
        h=objects(i);
        if ~ismember(h.Type,types), continue; end
        key=""; if isprop(h,o.SelectBy), key=string(h.(o.SelectBy)); end
        keep(i)=(isempty(o.Include) || ismember(key,string(o.Include))) && ...
            ~ismember(key,string(o.Exclude));
    end
    objects=objects(keep);
end

function styleObjects(root,style)
    props=fieldnames(style); if isempty(props), return; end
    objects=findall(root);
    for i=1:numel(objects)
        for j=1:numel(props)
            if isprop(objects(i),props{j}), set(objects(i),props{j},style.(props{j})); end
        end
    end
    % [CHANGE 6 BEGIN] Explicit labels opt copied objects into the legend.
    if isfield(style,'DisplayName') && strlength(string(style.DisplayName))>0 && ...
            isprop(root,'DisplayName') && isprop(root,'Annotation')
        root.Annotation.LegendInformation.IconDisplayStyle='on';
    end
    % [CHANGE 6 END]
end

function updateLegend(ax,objects)
    handles=gobjects(0,1); names=strings(0,1);
    for i=1:numel(objects)
        h=objects(i); if ~isprop(h,'DisplayName'), continue; end
        name=string(h.DisplayName); if strlength(name)==0 || any(names==name), continue; end
        if isprop(h,'Annotation') && strcmp(h.Annotation.LegendInformation.IconDisplayStyle,'off')
            continue;
        end
        handles(end+1,1)=h; names(end+1,1)=name; %#ok<AGROW>
    end
    if ~isempty(handles), legend(ax,handles,cellstr(names),'AutoUpdate','off'); end
end

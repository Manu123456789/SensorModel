%% FIGURE COMPOSER - edit this section, then run the whole file (MATLAB R2020a+).
% Copies graphics from existing .fig files; no raw data or replots required.
% Supports Cartesian axes, subplot/tiledlayout, lines, patches, scatter and
% common charts/groups. Layout, labels, view and formatting come from BASE.
% Source/base must use the same units, coordinate frame and time reference.
% yyaxis, polar/geographic axes and standalone charts are outside this scope.
% copyobj does not preserve callbacks, app data or custom data-tip templates.
% Processing stays invisible. Reopen with openfig('Combined.fig','visible').

% REQUIRED INPUTS: SourceMap mode uses ONE base .fig and any source .fig files.
% To use the original pair/batch mode, set SourceMap={} below and specify
% either two directories or two individual .fig paths for source/base.
source = 'C:\Results\MonteCarlo'; % Convenience folder for paths in SourceMap.
base   = 'C:\Results\Nominal\Velocity.fig'; % Existing destination layout/content.
output = 'C:\Results\Combined';    % Output directory; originals are preserved.

% MANY SOURCES -> ONE BASE: each row = {source .fig path, source axes, base axes}.
% Axes keys are Tags (or Titles if AxesBy='Title'). '' automatically selects
% the only axes in a figure; if it has several axes, give the desired key.
% Source and base can have different numbers/arrangements of subplots.
% Repeat a base axes key to overlay multiple datasets onto that same tile.
% Paths may be full paths or relative to MATLAB's current folder.
o.SourceMap = {
    fullfile(source,'VelocityX.fig'),   '', 'VelocityX'
    fullfile(source,'VelocityY.fig'),   '', 'VelocityY'
    fullfile(source,'VelocityZ.fig'),   '', 'VelocityZ'
    fullfile(source,'VelocityRSS.fig'), '', 'VelocityRSS'
};
% Set o.SourceMap={} to return to the original directory/file-pair workflow.
% OPTIONAL fourth column: a struct overriding settings for THAT ROW only.
% All rows must then have four columns; use struct() to inherit all defaults.
% Allowed overrides: SelectBy, Include, Exclude, Style, Layer.
% Example: add this fourth entry to one row to copy MC patches behind curves:
% struct('SelectBy','Tag','Include',{{'MonteCarlo'}},'Exclude',{{}},'Layer','bottom')
% Example for a thicker dashed line (Style replaces the global Style struct):
% struct('Include',{{'Modified Y'}},'Style',struct('LineStyle','--','LineWidth',1.5))

% DIRECTORY MODE: {} matches common filenames. Or specify only these pairs:
% {'MCVelocity.fig','Velocity.fig'; 'MCTrajectory.fig','Trajectory.fig'}
% Columns = source filename, base filename. Output uses the BASE filename.
o.FileMap = {};

% AXES MATCHING: 'Tag' recommended; 'Title' for older, untagged figures.
% Matching keys must be unique/nonempty. A single axes needs no key.
% Example when plotting: axX.Tag='VelocityX'; axRSS.Tag='VelocityRSS';
% Existing figures need no tags if their titles uniquely identify the axes:
% choose 'Title', then use the exact title text in SourceMap/AxesMap.
o.AxesBy = 'Tag';
% {} matches equal keys. Explicit mappings can rename/select particular axes:
% {'MC_X','VelocityX'; 'MC_Y','VelocityY'; 'MC_RSS','VelocityRSS'}
% Columns = source key, base key (Tag or Title, according to AxesBy).
% FileMap and AxesMap are only used when SourceMap is empty.
o.AxesMap = {};

% OBJECT SELECTION: exact, case-sensitive Tag OR DisplayName of plot objects.
% Selects direct axes children; tag the GROUP to copy a grouped dataset.
% Example: plot(ax,t,y,'Tag','ModifiedY','DisplayName','Modified Y');
% Example: h=patch(...); h.Tag='MonteCarlo'; (tag every MC patch/group).
o.SelectBy = 'DisplayName';        % 'Tag' or 'DisplayName'.
o.Include = {};                   % {} = all; {'Modified Y'} = only that data.
o.Exclude = {'Baseline'};         % Exclude wins; avoids a second baseline.
% MC preset: SelectBy='Tag'; Include={'MonteCarlo'}; Exclude={}; Layer='bottom'.
% Nothing is automatically deduplicated by name (many MC objects share a tag).

% STYLE OVERRIDES: applied ONLY to copies; struct() preserves source styles.
o.Style = struct();
% o.Style = struct('LineStyle','--','LineWidth',1.5,'Color',[0.8 0.2 0.1]);
% MC patches: struct('EdgeColor',[0.5 0.5 0.5],'EdgeAlpha',0.12);
% Filled bands: struct('FaceColor',[0.5 0.5 0.5],'FaceAlpha',0.12);
% Unsupported properties are ignored; invalid values fail that figure.
% Group descendants receive overrides too. Use RGB Color (not RGBA).

o.Layer = 'top';                  % 'bottom' keeps base curves above MC clouds.
o.Limits = 'base';                % 'base' fixes base limits; 'auto' fits all data.
o.Legend = 'update';              % 'keep' preserves base entries; 'update' below.
% 'update' rebuilds from named plots, base first; unnamed/legend-hidden plots
% are omitted. Repeated names get one entry (useful for Monte Carlo clouds).
% Use 'keep' for custom legend labels or a manually curated/shared legend.
o.Overwrite = true;               % Re-running replaces output, not input.
o.PNG = false;                    % Optional 200-dpi PNG beside each .fig.
% For hundreds of runs, build SourceMap/base/output inside your run-ID loop,
% then call composeFigures there. Output uses the base .fig filename.
composeFigures(source,base,output,o);

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
            warning('Composer:Failed','%s: %s',bases(k),ME.message);
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
    savefig(fig,output);
    if o.PNG
        [folder,name] = fileparts(output);
        png=fullfile(folder,name+".png");
        try
            assert(o.Overwrite || ~isfile(png),'PNG output already exists.');
            exportgraphics(fig,png,'Resolution',200);
        catch ME
            warning('Composer:PNG','FIG saved, but PNG export failed: %s',ME.message);
        end
    end
end

function key = axesKey(ax,by)
    if strcmp(by,'Tag'), key=string(ax.Tag);
    else, key=strjoin(string(ax.Title.String)," "); end
end

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
    o.AxesBy=validatestring(o.AxesBy,{'Tag','Title'});
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

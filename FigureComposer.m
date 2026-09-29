%% FIGURE COMPOSER - edit this section, then run the whole file (MATLAB R2020a+).
% Copies graphics from existing .fig files; no raw data or replots required.
% Supports Cartesian axes, subplot/tiledlayout, lines, patches, scatter and
% common charts/groups. Layout, labels, view and formatting come from BASE.
% Source/base must use the same units, coordinate frame and time reference.
% yyaxis, polar/geographic axes and standalone charts are outside this scope.
% copyobj does not preserve callbacks, app data or custom data-tip templates.
% Processing stays invisible. Reopen with openfig('Combined.fig','visible').

% REQUIRED INPUTS: both directories OR both individual .fig paths.
source = 'C:\Results\ModifiedY';   % Graphics to copy FROM (e.g. MonteCarlo).
base   = 'C:\Results\ModifiedX';   % Figure layout/content to copy INTO.
output = 'C:\Results\Combined';    % Output directory; originals are preserved.

% DIRECTORY MODE: {} matches common filenames. Or specify only these pairs:
% {'MCVelocity.fig','Velocity.fig'; 'MCTrajectory.fig','Trajectory.fig'}
% Columns = source filename, base filename. Output uses the BASE filename.
o.FileMap = {};

% AXES MATCHING: 'Tag' recommended; 'Title' for older, untagged figures.
% Matching keys must be unique/nonempty. A single axes needs no key.
% Example when plotting: axX.Tag='VelocityX'; axRSS.Tag='VelocityRSS';
o.AxesBy = 'Tag';
% {} matches equal keys. Explicit mappings can rename/select particular axes:
% {'MC_X','VelocityX'; 'MC_Y','VelocityY'; 'MC_RSS','VelocityRSS'}
% Columns = source key, base key (Tag or Title, according to AxesBy).
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
% For multiple source sets: use the previous output as BASE, with a NEW output
% directory. For hundreds of run folders: put the following call in your loop.
composeFigures(source,base,output,o);

%% Implementation - no edits normally needed below this line.
function composeFigures(source,base,output,o)
    o.AxesBy=validatestring(o.AxesBy,{'Tag','Title'});
    o.SelectBy=validatestring(o.SelectBy,{'Tag','DisplayName'});
    o.Layer=validatestring(o.Layer,{'top','bottom'});
    o.Limits=validatestring(o.Limits,{'base','auto'});
    o.Legend=validatestring(o.Legend,{'keep','update'});
    assert(isempty(o.FileMap) || size(o.FileMap,2)==2,'FileMap needs two columns.');
    assert(isempty(o.AxesMap) || size(o.AxesMap,2)==2,'AxesMap needs two columns.');
    if isfolder(source) && isfolder(base)
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
    outputs = strings(size(bases));
    for k=1:numel(bases)
        [ok,a] = fileattrib(sources(k)); assert(ok,'Missing source: %s',sources(k));
        sources(k) = string(a.Name);
        [ok,a] = fileattrib(bases(k)); assert(ok,'Missing base: %s',bases(k));
        bases(k) = string(a.Name);
        [~,name,ext] = fileparts(bases(k));
        [~,~,sourceExt] = fileparts(sources(k));
        assert(strcmpi(ext,'.fig') && strcmpi(sourceExt,'.fig'),'Inputs must be .fig files.');
        outputs(k) = fullfile(string(info.Name),name+ext);
    end
    inputs = [sources;bases]; checkOutputs = outputs;
    if ispc, inputs=lower(inputs); checkOutputs=lower(checkOutputs); end
    assert(~any(ismember(checkOutputs,inputs)),'Output must not overwrite ANY source/base figure.');
    assert(numel(unique(checkOutputs))==numel(outputs),'FileMap has duplicate output filenames.');
    % Include HandleVisibility='off' MC objects; restore root setting on exit.
    hidden = get(groot,'ShowHiddenHandles');
    restore = onCleanup(@()set(groot,'ShowHiddenHandles',hidden)); %#ok<NASGU>
    set(groot,'ShowHiddenHandles','on');
    saved = 0;
    for k=1:numel(sources)
        try
            assert(o.Overwrite || ~isfile(outputs(k)),'Output exists: %s',outputs(k));
            n = composeOne(sources(k),bases(k),outputs(k),o);
            fprintf('Saved %s (%d objects copied)\n',outputs(k),n);
            saved = saved+1;
        catch ME
            warning('Composer:Failed','%s: %s',bases(k),ME.message);
        end
    end
    fprintf('Completed: %d/%d figures saved.\n',saved,numel(sources));
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
        objects = selected(from(j),o);
        if isempty(objects), continue; end
        ax = to(j);
        assert(numel(from(j).YAxis)==1 && numel(ax.YAxis)==1,'yyaxis is not supported.');
        limits = {ax.XLim,ax.YLim,ax.ZLim}; old = ax.Children;
        if ~isempty(ax.Legend), ax.Legend.AutoUpdate='off'; end
        copied = gobjects(numel(objects),1);
        % Bottom-to-top source order; copying never clears existing graphics.
        for i=1:numel(objects)
            copied(i)=copyobj(objects(i),ax);
            styleObjects(copied(i),o.Style);
        end
        if strcmp(o.Layer,'bottom')
            ax.Children=[old;flipud(copied)];
        else
            ax.Children=[flipud(copied);old];
        end
        % Child ordering controls 2-D overlays; retain depth sorting for 3-D.
        if isequal(ax.View,[0 90]), ax.SortMethod='childorder'; end
        if strcmp(o.Legend,'update'), updateLegend(ax,[flipud(old);copied]); end
        if strcmp(o.Limits,'base')
            set(ax,'XLim',limits{1},'YLim',limits{2},'ZLim',limits{3});
        else
            set(ax,'XLimMode','auto','YLimMode','auto','ZLimMode','auto');
        end
        count = count+numel(copied);
    end
    assert(count>0,'No objects selected. Check Include/Exclude and object identifiers.');
    savefig(b,output);
    if o.PNG
        [folder,name] = fileparts(output);
        png=fullfile(folder,name+".png");
        try
            assert(o.Overwrite || ~isfile(png),'PNG output already exists.');
            exportgraphics(b,png,'Resolution',200);
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
    assert(strlength(key)>0,'Empty axes key. Add Tags, use Titles or set AxesMap.');
    matches = arrayfun(@(a)strcmp(axesKey(a,by),key),axesList);
    assert(nnz(matches)==1,'Axes key "%s" must match exactly once (%d matches).',key,nnz(matches));
    ax = axesList(matches);
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

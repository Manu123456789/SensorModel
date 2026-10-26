%% Accelerometer error histories and XYZ histograms in micro-g (ug)
% Standalone MATLAB R2021b script. No additional toolboxes are needed.
% Default input: instantaneous acceleration in ft/s^2, NOT gyro data.
% Use an interval with known true input/orientation; retain anomalous switching.
% Use native-rate samples. Subtract only the known baseline, NOT the data mean.
% Outputs: Results_sensor/Results_PLT (sample histories), HistogramResults.
% Histograms describe level occupancy, not switching order or dwell times.

%% 1. EDIT INPUTS
T = YourIMUTable;                    % Imported table; EDIT name and columns
% Or replace the line above with:
% T = readtable('IMU.xlsx','Sheet',1,'VariableNamingRule','preserve');
time_s = T.Time;                     % Numeric time [s], same rows as XYZ
X = T.ColumnX; Y = T.ColumnY; Z = T.ColumnZ;
% Without a time column, replace time_s above with:
% FsIn = 1000; time_s = (0:numel(X)-1)'/FsIn;
% For datetime timestamps: time_s = seconds(T.Time-T.Time(1));

inputMode = 'instantaneous_ft_s2';    % RECOMMENDED
% Optional modes: select ONLY after confirming the logger's exact rule:
% 'sample_sum_cm_s2': C(k) = C(k-1) + a_cm_s2(k), unweighted cumulative sum.
% 'integral_cm_s':   C(k)-C(k-1) = intervalMean_a_cm_s2(k)*dt(k).
% The integral mode requires cumulative VELOCITY units cm/s, NOT cm/s^2.
% Running averages, sliding sums and counter-wrap formats need other decoding.

window_s = [NaN NaN];                % EDIT: [start end]; include low AND high states
baseline_sensor_ms2 = [NaN NaN NaN];  % EDIT: known true XYZ input [m/s^2]
% Use [0 0 0] only for a genuinely zero-input/gravity-compensated signal.
% A stationary raw accelerometer generally contains gravity. Include its actual
% signed sensor-axis projection in this baseline; do not estimate it as bias.
% Example ONLY for a known +Z 1-standard-g input: [0 0 9.80665].

R_sensor_to_PLT = eye(3);             % EDIT: fixed orthonormal 3x3 transform
% Column-vector convention: v_PLT = R_sensor_to_PLT * v_sensor.

% Optional known rail bounds. Rows are sensor X/Y/Z; columns are [lower upper].
% Values ON or outside a bound are flagged. Set bounds before a rail if needed.
rawLimits = [-Inf Inf; -Inf Inf; -Inf Inf]; % In selected table columns' units
accelLimits_ms2 = [-Inf Inf; -Inf Inf; -Inf Inf]; % Physical acceleration limits
% Raw limits can flag a clipped accumulator even when its difference is zero.
% Acceleration limits can flag clipping after reconstructing cumulative data.
% Inf bounds disable detection; they do NOT establish that data are unclipped.

excludedIntervals_s = zeros(0,2);     % EDIT if needed: [badStart badEnd; ...]
resetTimes_s = [];                   % EDIT: known cumulative reset/jump times
% Exclude only intervals you do not want analyzed (or cannot decode).
% Do not exclude the high/low switching you are trying to characterize.
makePlots = true;
histogramBins = 50;                  % EDIT: number of bins; full data range retained
includeFlaggedInHistograms = true;   % Keep finite rail-level readings to reveal clusters
% Flagged readings show the RECORDED values, not true acceleration beyond a rail.

%% 2. Validate data/configuration without deleting rows or changing timestamps
assert(isnumeric(X) && isnumeric(Y) && isnumeric(Z) && isnumeric(time_s) && ...
    isvector(X) && isvector(Y) && isvector(Z) && isvector(time_s) && ...
    numel(X)==numel(Y) && numel(Y)==numel(Z) && numel(Z)==numel(time_s), ...
    'Time and XYZ must be numeric vectors of equal length.');
raw = double([X(:) Y(:) Z(:)]); t = double(time_s(:));
assert(isreal(raw) && isreal(t) && numel(t)>=3 && ...
    all(isfinite(t)) && all(diff(t)>0), ...
    'Need at least three rows with finite, strictly increasing time in seconds.');
assert(isequal(size(window_s),[1 2]) && all(isfinite(window_s)) && ...
    window_s(1)<window_s(2) && window_s(1)>=t(1) && window_s(2)<=t(end), ...
    'Set window_s = [start end] within the recorded time range.');
assert(isequal(size(baseline_sensor_ms2),[1 3]) && ...
    isreal(baseline_sensor_ms2) && all(isfinite(baseline_sensor_ms2)), ...
    'Supply the known true sensor-frame baseline as a finite 1x3 vector [m/s^2].');
R = R_sensor_to_PLT;
assert(isequal(size(R),[3 3]) && isreal(R) && all(isfinite(R(:))) && ...
    norm(R*R'-eye(3),'fro')<1e-6, 'Supply an orthonormal 3x3 frame transform.');
assert(isequal(size(rawLimits),[3 2]) && ...
    isequal(size(accelLimits_ms2),[3 2]) && ...
    all(rawLimits(:,1)<rawLimits(:,2)) && ...
    all(accelLimits_ms2(:,1)<accelLimits_ms2(:,2)), ...
    'Limits must be 3x2 arrays with lower < upper for each axis.');
assert(size(excludedIntervals_s,2)==2 && ...
    all(isfinite(excludedIntervals_s(:))) && ...
    all(excludedIntervals_s(:,1)<=excludedIntervals_s(:,2)), ...
    'excludedIntervals_s must have finite [start end] rows, or be zeros(0,2).');
assert(isnumeric(resetTimes_s) && all(isfinite(resetTimes_s(:))), ...
    'resetTimes_s must contain finite numeric times, or be empty.');
validateattributes(histogramBins,{'numeric'},{'scalar','integer','positive','finite'});
badRaw = any(~isfinite(raw) | raw<=rawLimits(:,1)' | raw>=rawLimits(:,2)',2);

%% 3. Convert/reconstruct acceleration in m/s^2, preserving every observed level
switch inputMode
    case 'instantaneous_ft_s2'
        a_sensor_ms2 = raw*0.3048;   % Exact international-foot conversion
        tA = t; leftTime = t; rightTime = t;
        bad = badRaw;
    case {'sample_sum_cm_s2','integral_cm_s'}
        leftTime = t(1:end-1); rightTime = t(2:end); tA = rightTime;
        a_sensor_ms2 = diff(raw,1,1)*0.01;
        bad = badRaw(1:end-1) | badRaw(2:end);
        if strcmp(inputMode,'integral_cm_s')
            a_sensor_ms2 = a_sensor_ms2./diff(t);
        end
    otherwise
        error('Unknown inputMode. Use a documented mode from Section 1.');
end
bad = bad | any(~isfinite(a_sensor_ms2) | ...
    a_sensor_ms2<=accelLimits_ms2(:,1)' | ...
    a_sensor_ms2>=accelLimits_ms2(:,2)',2);
selected = tA>=window_s(1) & tA<=window_s(2);
if strcmp(inputMode,'integral_cm_s')
    selected = selected & leftTime>=window_s(1); % Whole intervals inside window
end
excluded = false(size(tA));
for j = 1:size(excludedIntervals_s,1)
    excluded = excluded | (leftTime<=excludedIntervals_s(j,2) & ...
        rightTime>=excludedIntervals_s(j,1));
end
if ~strcmp(inputMode,'instantaneous_ft_s2')
    for j = 1:numel(resetTimes_s)
        excluded = excluded | (leftTime<resetTimes_s(j) & rightTime>=resetTimes_s(j));
    end
end
use = selected & ~excluded & ~bad;   % ONE COMMON set of valid XYZ rows
rejected = selected & (excluded | bad);
g0 = 9.80665;                       % Standard gravity [m/s^2]
residual_sensor_ug = (a_sensor_ms2-baseline_sensor_ms2)*(1e6/g0);
% No mean subtraction: a recorded zero/high pattern keeps its original offset.

%% 4. Review the window and invalid rows; do not infer saturation from sign
if makePlots
    fig = figure('Name','Accelerometer error window - sensor frame');
    tiles = tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
    names = {'X','Y','Z'};
    for j = 1:3
        ax = nexttile(tiles,j);
        h1 = plot(ax,tA,residual_sensor_ug(:,j),'Color',[0.65 0.65 0.65]); hold(ax,'on');
        h2 = plot(ax,tA(use),residual_sensor_ug(use,j),'b.');
        h3 = plot(ax,tA(rejected),residual_sensor_ug(rejected,j),'rx');
        h4 = yline(ax,0,'k--');
        xline(ax,window_s(1),'k:','HandleVisibility','off');
        xline(ax,window_s(2),'k:','HandleVisibility','off'); grid(ax,'on');
        ylabel(ax,[names{j} ' residual [\mug]']);
        legend(ax,[h1 h2 h3 h4],{'Recorded minus baseline','Within-bounds XYZ rows', ...
            'Flagged/excluded XYZ rows','Zero error'},'Location','best');
    end
    xlabel(ax,'Time [s]');
    title(tiles,'Observed sensor-frame error: selected window and flagged/excluded rows');
end

%% 5. NEW: retain full error histories, then histogram sensor AND PLT XYZ
% A single mean/RMS cannot retain the observed switching sequence.
histUse = selected & ~excluded & all(isfinite(residual_sensor_ug),2);
if ~includeFlaggedInHistograms
    histUse = histUse & ~bad;
end
assert(nnz(histUse)>=2, 'Fewer than two common finite XYZ samples remain.');
error_sensor_ug = residual_sensor_ug(histUse,:);
error_PLT_ug = error_sensor_ug*R';     % Rotate synchronized SAMPLES, not histograms
limitFlag = bad(histUse);
Results_sensor = table(tA(histUse),error_sensor_ug(:,1),error_sensor_ug(:,2), ...
    error_sensor_ug(:,3),limitFlag, ...
    'VariableNames',{'Time_s','ErrorX_ug','ErrorY_ug','ErrorZ_ug','LimitFlag'});
Results_PLT = table(tA(histUse),error_PLT_ug(:,1),error_PLT_ug(:,2), ...
    error_PLT_ug(:,3),limitFlag, ...
    'VariableNames',{'Time_s','ErrorX_ug','ErrorY_ug','ErrorZ_ug','LimitFlag'});
% Original timestamps, including any gaps, are retained for later modeling.
% LimitFlag means at least one source axis reached a configured bound.

names = {'X','Y','Z'};
HistogramResults = struct([]);
if makePlots
    figHist = figure('Name','Accelerometer error distributions - mean retained', ...
        'Position',[100 100 1100 850]);
    histTiles = tiledlayout(figHist,3,2,'TileSpacing','compact','Padding','compact');
    title(histTiles,'Selected interval: known baseline removed; measured mean retained');
end
for j = 1:3
    % Shared equal-width edges make sensor/PLT distributions comparable per row.
    [~,edges] = histcounts([error_sensor_ug(:,j); error_PLT_ug(:,j)],histogramBins);
    countsSensor = histcounts(error_sensor_ug(:,j),edges);
    countsPLT = histcounts(error_PLT_ug(:,j),edges);
    HistogramResults(j).Axis = names{j};
    HistogramResults(j).BinEdges_ug = edges;
    HistogramResults(j).SensorCounts = countsSensor;
    HistogramResults(j).PLTCounts = countsPLT;
    HistogramResults(j).SensorProbability = countsSensor/sum(countsSensor);
    HistogramResults(j).PLTProbability = countsPLT/sum(countsPLT);
    if makePlots
        axS = nexttile(histTiles,2*j-1);
        histogram(axS,error_sensor_ug(:,j),edges,'Normalization','probability');
        grid(axS,'on'); title(axS,['Sensor ' names{j}]);
        xlabel(axS,'Acceleration error [\mug]'); ylabel(axS,'Fraction of samples');
        axP = nexttile(histTiles,2*j);
        histogram(axP,error_PLT_ug(:,j),edges,'Normalization','probability');
        grid(axP,'on'); title(axP,['PLT ' names{j}]);
        xlabel(axP,'Acceleration error [\mug]'); ylabel(axP,'Fraction of samples');
    end
end
% Probabilities are fractions of SAMPLES. They approximate fractions of time
% only for uniform sampling. No fitted distribution or anomaly threshold is imposed.
fprintf('Retained %d XYZ samples in [%.6g, %.6g] s; %d retained rows have limit flags.\n', ...
    nnz(histUse),min(tA(histUse)),max(tA(histUse)),nnz(limitFlag));
fprintf('Results_PLT contains the full error history in micro-g, not a constant bias.\n');
% Optional export for later model identification (not a three-bias sim input):
% writetable(Results_PLT,'IMU_Error_History_PLT_ug.csv');

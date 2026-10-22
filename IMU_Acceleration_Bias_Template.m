%% Accelerometer bias in the PLT frame, reported in micro-g (ug)
% Standalone MATLAB R2021b script. No additional toolboxes are needed.
% Default input: instantaneous acceleration in ft/s^2, NOT gyro data.
% Estimate on a settled interval with constant known true input/orientation.
% Use native-rate samples; downsampling is unnecessary for this bias estimate.
% Output: Results_PLT (only XYZ bias), plus numeric row vector bias_PLT_ug.

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

window_s = [NaN NaN];                % EDIT: [startTime endTime], in time_s units
baseline_sensor_ms2 = [NaN NaN NaN];  % EDIT: known true XYZ input [m/s^2]
% Use [0 0 0] only for a genuinely zero-input/gravity-compensated signal.
% A stationary raw accelerometer generally contains gravity. Include its actual
% signed sensor-axis projection in this baseline; do not estimate it as bias.
% Example ONLY for a known +Z 1-standard-g input: [0 0 9.80665].

R_sensor_to_PLT = eye(3);             % EDIT: fixed orthonormal 3x3 transform
% Column-vector convention: v_PLT = R_sensor_to_PLT * v_sensor.

% Optional known rail bounds. Rows are sensor X/Y/Z; columns are [lower upper].
% Values ON or outside a bound are invalid. Set bounds before a rail if needed.
rawLimits = [-Inf Inf; -Inf Inf; -Inf Inf]; % In selected table columns' units
accelLimits_ms2 = [-Inf Inf; -Inf Inf; -Inf Inf]; % Physical acceleration limits
% Raw limits can flag a clipped accumulator even when its difference is zero.
% Acceleration limits can flag clipping after reconstructing cumulative data.
% Inf bounds disable detection; they do NOT establish that data are unclipped.

excludedIntervals_s = zeros(0,2);     % EDIT if needed: [badStart badEnd; ...]
resetTimes_s = [];                   % EDIT: known cumulative reset/jump times
% Exclude complete bad/transient intervals, not just clipped peaks. Prefer a
% window wholly before saturation. Never substitute zero for an invalid axis.
makePlots = true;

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
badRaw = any(~isfinite(raw) | raw<=rawLimits(:,1)' | raw>=rawLimits(:,2)',2);

%% 3. Convert/reconstruct acceleration in m/s^2 BEFORE estimating bias
switch inputMode
    case 'instantaneous_ft_s2'
        a_sensor_ms2 = raw*0.3048;   % Exact international-foot conversion
        tA = t; leftTime = t; rightTime = t;
        bad = badRaw; weights = ones(size(t));
    case {'sample_sum_cm_s2','integral_cm_s'}
        leftTime = t(1:end-1); rightTime = t(2:end); tA = rightTime;
        a_sensor_ms2 = diff(raw,1,1)*0.01;
        bad = badRaw(1:end-1) | badRaw(2:end);
        weights = ones(size(tA));
        if strcmp(inputMode,'integral_cm_s')
            weights = diff(t);      % Duration weights for interval means
            a_sensor_ms2 = a_sensor_ms2./weights;
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

%% 4. Review the window and invalid rows; do not infer saturation from sign
if makePlots
    fig = figure('Name','Accelerometer bias window - sensor frame');
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
        legend(ax,[h1 h2 h3 h4],{'Recorded minus baseline','Used XYZ rows', ...
            'Rejected/excluded XYZ rows','Zero error'},'Location','best');
    end
    xlabel(ax,'Time [s]');
    title(tiles,'Sensor-frame acceleration error: select a settled, unclipped window');
end

% Fail rather than silently estimate from a partially clipped distribution.
assert(~any(selected & ~excluded & bad), ...
    ['Window contains saturated/nonfinite XYZ rows. Choose a clean window or ' ...
     'explicitly exclude complete bad intervals. Clipped values cannot recover bias.']);
assert(nnz(use)>=2, 'Fewer than two common valid XYZ samples remain.');

%% 5. Bias in the sensor frame -> PLT frame -> micro-g
mean_sensor_ms2 = sum(a_sensor_ms2(use,:).*weights(use),1)/sum(weights(use));
bias_sensor_ms2 = mean_sensor_ms2-baseline_sensor_ms2;
bias_sensor_ug = bias_sensor_ms2*(1e6/g0);
bias_PLT_ug = (bias_sensor_ms2*R')*(1e6/g0);
% Signed additive-error convention: measurement = truth + bias.
% A simulation correction parameter would instead use the negative of this bias.
Results_PLT = table(bias_PLT_ug(1),bias_PLT_ug(2),bias_PLT_ug(3), ...
    'VariableNames',{'BiasX_ug','BiasY_ug','BiasZ_ug'});
disp(Results_PLT);
fprintf('Used %d common XYZ rows in [%.6g, %.6g] s; excluded %d selected rows.\n', ...
    nnz(use),min(tA(use)),max(tA(use)),nnz(rejected));
% Optional export for your sim:
% writetable(Results_PLT,'IMU_Bias_PLT_ug.csv');

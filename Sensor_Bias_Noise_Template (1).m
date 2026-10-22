%% Sensor bias, noise RMS, PSD, FFT and Allan analysis in a fixed PLT frame
% MATLAB R2021b-compatible syntax; requires Signal Processing Toolbox.
% Input: synchronous, uniformly sampled numeric X/Y/Z columns.
% Use constant-input/stationary intervals with a known baseline.
% Output: Results_PLT, one row per selected interval; Spectra{i} stores spectra.
% Noise is mean-removed data: its RMS includes tones and any remaining drift.

%% 1. EDIT THESE INPUTS (leave your imported table in the workspace)
T = YourTable;                       % EDIT: imported MATLAB table name
X = T.ColumnX;                       % EDIT: column names
Y = T.ColumnY;
Z = T.ColumnZ;
FsIn  = NaN;                         % EDIT: original sampling rate [Hz]
FsOut = NaN;                         % EDIT: desired sampling rate [Hz]
rateScale = 1;                       % 1 for deg/s; FsIn for deg/original sample
baseline_sensor = [0 0 0];           % EDIT: known true rate [deg/s], SENSOR frame
R_sensor_to_PLT = eye(3);             % EDIT: fixed 3x3 orthonormal transform
% Convention: v_PLT = R_sensor_to_PLT * v_sensor for 3x1 column vectors.
% If your matrix maps PLT -> sensor, transpose it before assigning it above.

TS = 1;                             % EDIT: original start SAMPLE index/indices
TE = numel(X);                      % EDIT: original end SAMPLE index/indices
% Example: TS = [1001 5001]; TE = [4000 8000]; selects two separate intervals.
% If specifying seconds from the first sample instead, use:
% TS = ceil(startSeconds*FsIn) + 1; TE = floor(endSeconds*FsIn) + 1;
useAntialias = true;                 % false: literal 1:NDS:end (integer ratio)
makePlots = true;
plotAllanVariance = false;           % Tile 3: false = deviation; true = variance

%% 2. Check inputs and downsample
validateattributes(FsIn, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(FsOut, {'numeric'}, {'scalar','real','finite','positive'});
validateattributes(rateScale, {'numeric'}, {'scalar','real','finite','positive'});
assert(FsOut <= FsIn, 'FsOut must be no larger than FsIn.');
assert(isnumeric(X) && isnumeric(Y) && isnumeric(Z) && ...
    isvector(X) && isvector(Y) && isvector(Z) && ...
    numel(X)==numel(Y) && numel(Y)==numel(Z), ...
    'X/Y/Z must be numeric vectors of equal length.');
XYZ = double([X(:) Y(:) Z(:)]);
assert(isreal(XYZ) && all(isfinite(XYZ(:))), ...
    'Fix NaN/Inf in place before running; deleting rows changes timing/indices.');
assert(isequal(size(baseline_sensor),[1 3]) && ...
    isreal(baseline_sensor) && all(isfinite(baseline_sensor)), ...
    'baseline_sensor must be a finite 1x3 row vector in deg/s.');
assert(isequal(size(R_sensor_to_PLT),[3 3]) && ...
    isreal(R_sensor_to_PLT) && all(isfinite(R_sensor_to_PLT(:))) && ...
    norm(R_sensor_to_PLT*R_sensor_to_PLT'-eye(3),'fro') < 1e-6, ...
    'R_sensor_to_PLT must be a finite, orthonormal 3x3 matrix.');
TS = TS(:); TE = TE(:);
assert(~isempty(TS) && numel(TS)==numel(TE) && ...
    all(isfinite(TS)) && all(isfinite(TE)) && ...
    all(TS==round(TS)) && all(TE==round(TE)) && ...
    all(TS>=1 & TE>=TS & TE<=size(XYZ,1)), ...
    'TS/TE must be matching valid 1-based original sample indices.');

NDS = FsIn/FsOut;
if FsOut == FsIn
    XYZ_DS = XYZ;
elseif useAntialias
    [pDS,qDS] = rat(FsOut/FsIn,1e-12);
    assert(abs(FsIn*pDS/qDS-FsOut) <= 1e-9*FsOut, ...
        'Resampling ratio is insufficiently accurate for these rates.');
    offset = mean(XYZ,1);            % Reduce filtering transients from large DC
    XYZ_DS = resample(XYZ-offset,pDS,qDS) + offset;
    % Select intervals away from record edges/transitions if transients matter.
else
    assert(abs(NDS-round(NDS)) < 1e-10, ...
        '1:NDS:end requires an integer FsIn/FsOut; useAntialias=true otherwise.');
    XYZ_DS = XYZ(1:round(NDS):end,:); % Your X_DS = X(1:NDS:end), for all 3 axes
    % This branch requires data already bandlimited below FsOut/2.
end
X_DS = XYZ_DS(:,1); Y_DS = XYZ_DS(:,2); Z_DS = XYZ_DS(:,3);
TSDS = ceil((TS-1)/NDS) + 1;
TEDS = floor((TE-1)/NDS) + 1;
assert(all(TSDS>=1 & TEDS<=size(XYZ_DS,1) & TEDS-TSDS+1>=16), ...
    'Each selected interval must contain at least 16 downsampled points.');

%% 3. Bias/noise in sensor frame, then convert to PLT and calculate spectra
nSegments = numel(TSDS);
bias_sensor = zeros(nSegments,3); noiseRMS_sensor = zeros(nSegments,3);
bias_PLT = zeros(nSegments,3); noiseRMS_PLT = zeros(nSegments,3);
Spectra = cell(nSegments,1);
for i = 1:nSegments
    XR = [X_DS(TSDS(i):TEDS(i)) Y_DS(TSDS(i):TEDS(i)) ...
          Z_DS(TSDS(i):TEDS(i))] * rateScale;             % [deg/s], N x 3
    meanRate = mean(XR,1);
    bias_sensor(i,:) = (meanRate-baseline_sensor)*3600;   % [deg/hour]
    noiseData = XR-meanRate;                             % Remove bias/DC
    noise_u = deg2rad(noiseData)*1e6;                    % [microrad/s]
    [PXX,F] = pwelch(noise_u,[],[],[],FsOut);
    noiseRMS_sensor(i,:) = sqrt(trapz(F,PXX,1));          % [microrad/s]

    % Rotate signed bias and synchronized noise SAMPLES, not the RMS vector.
    bias_PLT(i,:) = bias_sensor(i,:)*R_sensor_to_PLT';
    noise_PLT_u = noise_u*R_sensor_to_PLT';
    [PXX_PLT,F] = pwelch(noise_PLT_u,[],[],[],FsOut);
    noiseRMS_PLT(i,:) = sqrt(trapz(F,PXX_PLT,1));

    % One-sided, Hann-windowed FFT: coherent-gain-corrected peak amplitude.
    % First 3 columns are sensor XYZ; last 3 are PLT XYZ.
    L = size(noise_u,1); w = hann(L,'periodic');
    A = abs(fft([noise_u noise_PLT_u].*w,[],1))/sum(w);
    A = A(1:floor(L/2)+1,:);
    A(2:ceil(L/2),:) = 2*A(2:ceil(L/2),:);   % Leave DC/Nyquist undoubled
    Ffft = (0:floor(L/2))'*FsOut/L;

    % Overlapping Allan variance: half the mean squared difference between
    % adjacent m-sample rate averages. No additional toolbox is needed.
    % First 3 columns are sensor XYZ; last 3 are PLT XYZ, as for the FFT.
    mAllan = unique(round(logspace(0,log10(floor((L-1)/2)),50)))';
    tauAllan = mAllan/FsOut;                             % Averaging time [s]
    sums = [zeros(1,6); cumsum([noise_u noise_PLT_u],1)];
    avar = zeros(numel(mAllan),6);
    for k = 1:numel(mAllan)
        m = mAllan(k);
        deltaMean = (sums(1+2*m:end,:) - ...
            2*sums(1+m:end-m,:) + sums(1:end-2*m,:))/m;
        avar(k,:) = 0.5*mean(deltaMean.^2,1);             % [(microrad/s)^2]
    end
    adev = sqrt(avar);                                  % [microrad/s]

    Spectra{i} = struct('PSD_F_Hz',F, 'PSD_sensor',PXX, ...
        'PSD_PLT',PXX_PLT, 'FFT_F_Hz',Ffft, ...
        'FFT_sensor',A(:,1:3), 'FFT_PLT',A(:,4:6), ...
        'Allan_Tau_s',tauAllan, ...
        'AllanVar_sensor',avar(:,1:3), 'AllanVar_PLT',avar(:,4:6), ...
        'AllanDev_sensor',adev(:,1:3), 'AllanDev_PLT',adev(:,4:6));
    % PSD units: (microrad/s)^2/Hz. FFT units: microrad/s peak.
    % FFT peaks locate candidate tones; off-bin tones can underestimate amplitude.

    if makePlots
        fig = figure('Name',sprintf('Segment %d - PLT frame',i), ...
            'Position',[100 100 1000 900]);
        tiles = tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
        title(tiles,sprintf('Segment %d: mean-removed PLT noise',i));
        nexttile(tiles,1);
        loglog(F(2:end),PXX_PLT(2:end,:)); grid on;
        xlabel('Frequency [Hz]'); ylabel('PSD [(\murad/s)^2/Hz]');
        title('Power spectral density');
        legend('X','Y','Z','Location','best');
        nexttile(tiles,2);
        plot(Ffft,A(:,4:6)); grid on; xlim([0 FsOut/2]);
        xlabel('Frequency [Hz]'); ylabel('FFT peak amplitude [\murad/s]');
        title('FFT');
        legend('X','Y','Z','Location','best');
        nexttile(tiles,3);
        if plotAllanVariance
            loglog(tauAllan,avar(:,4:6));
            ylabel('Allan variance [(\murad/s)^2]'); title('Allan variance');
        else
            loglog(tauAllan,adev(:,4:6));
            ylabel('Allan deviation [\murad/s]'); title('Allan deviation');
        end
        grid on; xlabel('Averaging time \tau [s]');
        legend('X','Y','Z','Location','best');
    end
end

%% 4. Final table: X/Y/Z bias and integrated noise RMS in the PLT frame
Results_PLT = table((1:nSegments)', ...
    bias_PLT(:,1),bias_PLT(:,2),bias_PLT(:,3), ...
    noiseRMS_PLT(:,1),noiseRMS_PLT(:,2),noiseRMS_PLT(:,3), ...
    'VariableNames',{'Segment','BiasX_deg_hr','BiasY_deg_hr','BiasZ_deg_hr', ...
    'NoiseX_urad_s','NoiseY_urad_s','NoiseZ_urad_s'});
disp(Results_PLT);
% Optional export; change the filename to suit the receiving tool:
% writetable(Results_PLT,'Sensor_Bias_Noise_PLT.csv');

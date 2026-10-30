%% STANDALONE ACCELEROMETER FOURIER TIME-SERIES GENERATOR -- MATLAB R2021b
% Run AFTER IMU_Config.m, or load a previously saved coefficient MAT file.
% This ONE file needs base MATLAB only. No +imufourier folder is required.
% Do not clear the workspace: IMU_Results contains the fitted coefficients.
%
% Generated signal, on each selected SENSOR axis:
%   error_ug(t) = mean_ug + sum(A*sin(2*pi*f*t + phase)) + sigma*randn.
%
% The generator receives ONLY model coefficients, never the measured history,
% fittedHistory or original FFT. Optional measured data is used AFTER generation
% solely for the residual comparison figure.
%
% DEFAULT BEHAVIOR:
%   Three fitted-record periods, one realization, inherited phase/noise settings.
%   Aligned phases + zero white sigma => the SAME output every run and cycle.
%   A random circular start shifts the SAME spike pattern; it does not draw new
%   spike heights or arrival times. Fresh white noise is optional, not automatic.
%   A full-order match verifies reconstruction of this fitted recording. The
%   repeating waveform does not establish new, independent stochastic spikes.
%   Extending duration does not add measured evidence or change the fit.
%   Keep Fs and recordSamples unchanged when extending the simulation.
%
% CLEAN-SESSION WORKFLOW (do this once after identification):
%   FourierModel = IMU_Results.model;
%   save('MyAccelCoefficients.mat','FourierModel');
% Then copy this script and that MAT file anywhere. Set inputSource='matfile'
% and modelMatFile='MyAccelCoefficients.mat' below. The package's own saved
% output_hardware/IMU_Results.mat also contains a compact FourierModel variable;
% this script loads that variable without loading the large analysis results.
%
% OUTPUT:
%   IMU_Fourier_Standalone.time_s                 [samples x 1], seconds
%   IMU_Fourier_Standalone.error_sensor_ug        [samples x 3 x realizations]
%   IMU_Fourier_Standalone.onePeriod_sensor_ug    [Nfit x 3], no fresh white
%   IMU_Fourier_Standalone.modelUsed             actual retained coefficients
%   IMU_Fourier_Standalone.coefficientInfo       counts and direct-sine check
%   IMU_Fourier_Standalone.runInfo               shifts and run differences
% Unselected SENSOR-axis columns are zero; this is only the standalone model
% contribution, not the complete three-axis legacy simulation measurement.
%
% The output is acceleration ERROR in micro-g, before frame rotation. If needed:
%   error_ft_s2 = IMU_Fourier_Standalone.error_sensor_ug .* (9.80665e-6/0.3048);
%   delta_v_ft_s = error_ft_s2 ./ IMU_Fourier_Standalone.Fs_Hz;
% Do not difference this acceleration against the previous noise sample.

%% USER SETTINGS -- all changes go in this box.
standaloneCfg = struct;
standaloneCfg.inputSource = 'workspace';  % 'workspace' or 'matfile'.
standaloneCfg.workspaceVariable = 'IMU_Results'; % Or 'FourierModel'.
standaloneCfg.modelMatFile = 'MyAccelCoefficients.mat';

standaloneCfg.duration_s = [];           % [] = 3*Nfit/Fs. Or set seconds, e.g. 120.
standaloneCfg.nRealizations = 1;          % Set 10 to compare ten realizations.
standaloneCfg.seed = 1234;                % Same settings/seed reproduce a batch.
standaloneCfg.phaseMode = 'model';        % 'model', 'aligned', 'randomCircularShift'.
standaloneCfg.whiteSigmaOverride_ug = []; % [] keeps fitted sigma. 0 disables it.
% A nonnegative scalar overrides all selected axes; a 1x3 vector overrides XYZ.
% Arbitrary added white noise changes the fit; this control is a what-if test.
% With full Fourier, fitted quiet-residual white sigma is normally zero.

standaloneCfg.maxTones = Inf;             % Keep all EXPORTED tones, or try 64/256/512.
standaloneCfg.toneSelection = 'energy';   % 'energy' or 'lowFrequency'.
% This only DROPS exported tones. It cannot recover tones omitted during fitting,
% and does not refit residual white sigma. For a new fit, use cfg.maxTones in
% IMU_Config.m and rerun identification (especially if fitting residual noise).

standaloneCfg.synthesisMethod = 'ifft';   % 'ifft' (fast) or 'sines' (literal sum).
% Both use only the same frequency/amplitude/phase arrays. The inverse FFT is
% the same sampled sine sum on the package's harmonic grid, up to roundoff.
% It builds a period FROM coefficients, not from a stored measured waveform.
% 'sines' is analogous to C++ and costs O(Nfit*K); it can be slow for large K.
% A small direct-sine check runs for BOTH choices, including the Nyquist term.

standaloneCfg.plotAxis = '';              % '' = first selected axis; or 'X'/'Y'/'Z'.
standaloneCfg.zoomHalfWidth_samples = 25; % Mark every sample around largest peak.
standaloneCfg.compareFitRecord = true;    % Optional: use IMU_Results.train if present.
standaloneCfg.makePlots = true;
standaloneCfg.figureVisible = 'on';       % Set 'off' for batch execution.

%% GET COEFFICIENTS -- no fitting, package functions or raw-data import.
if strcmp(standaloneCfg.inputSource,'workspace')
    assert(isvarname(standaloneCfg.workspaceVariable),'Use one workspace variable name.');
    assert(exist(standaloneCfg.workspaceVariable,'var')==1, ...
        ['Run identification or load the model first: missing ' standaloneCfg.workspaceVariable]);
    standaloneInput = eval(standaloneCfg.workspaceVariable);
elseif strcmp(standaloneCfg.inputSource,'matfile')
    assert(isfile(standaloneCfg.modelMatFile),'Set modelMatFile to your saved coefficient MAT file.');
    standaloneVariables = who('-file',standaloneCfg.modelMatFile);
    if ismember('FourierModel',standaloneVariables)
        standaloneLoaded = load(standaloneCfg.modelMatFile,'FourierModel');
        standaloneInput = standaloneLoaded.FourierModel;
    elseif ismember('IMU_Results',standaloneVariables)
        standaloneLoaded = load(standaloneCfg.modelMatFile,'IMU_Results');
        standaloneInput = standaloneLoaded.IMU_Results;
    else
        error('The MAT file must contain FourierModel or IMU_Results.');
    end
else
    error('inputSource must be workspace or matfile.');
end

standaloneReference = [];
if isstruct(standaloneInput) && isfield(standaloneInput,'model')
    if standaloneCfg.compareFitRecord && isfield(standaloneInput,'train')
        standaloneReference = standaloneInput.train; % Comparison ONLY, not synthesis.
    end
    standaloneModel = standaloneInput.model;
else
    standaloneModel = standaloneInput;
end

% Neither the original results nor measured reference enters this function.
IMU_Fourier_Standalone = localGenerate(standaloneModel,standaloneCfg);
IMU_Fourier_Standalone.fitComparison = localCompare( ...
    IMU_Fourier_Standalone,standaloneReference);
if standaloneCfg.makePlots
    localPlot(IMU_Fourier_Standalone,standaloneCfg,standaloneReference);
end
% Optional save: uncomment to retain the generated history as a MAT file.
% save('IMU_Fourier_Standalone_History.mat','IMU_Fourier_Standalone','-v7.3');

%% LOCAL FUNCTIONS -- keep these in this same file, below the script.
function out = localGenerate(input,c)
m = localCoefficients(input,c); fs=m.Fs; N=m.recordSamples;
if isempty(c.duration_s), requested=3*N/fs; else, requested=c.duration_s; end
validateattributes(requested,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(c.nRealizations,{'numeric'},{'scalar','integer','>=',1});
validateattributes(c.seed,{'numeric'},{'scalar','integer','>=',0,'<',2^32});
validateattributes(c.zoomHalfWidth_samples,{'numeric'},{'scalar','integer','>=',1});
assert(ismember(c.synthesisMethod,{'ifft','sines'}),'Choose ifft or sines synthesis.');
ns=round(requested*fs); assert(ns>=1,'Duration must contain at least one sample.');
R=c.nRealizations; period=zeros(N,3); directError=NaN(3,1); count=zeros(3,1);
for j=find(m.selectedMask)
    f=m.toneFreq{j}; a=m.toneAmp{j}; p=m.tonePhase{j}; b=m.toneBin{j};
    count(j)=numel(f);
    if strcmp(c.synthesisMethod,'sines')
        period(:,j)=localSines(f,a,p,fs,(0:N-1)',m.mean_ug(j));
    else
        % Recover positive/negative conjugate FFT pairs from SINE coefficients.
        F=zeros(N,1); C=(N/2)*a.*exp(1i*(p-pi/2)); paired=true(size(b));
        if mod(N,2)==0
            nyquist=b==N/2; paired(nyquist)=false;
            C(nyquist)=N*a(nyquist).*sin(p(nyquist)); % Real; NO factor of two.
        end
        F(b+1)=C; F(N-b(paired)+1)=conj(C(paired));
        period(:,j)=m.mean_ug(j)+real(ifft(F));
    end
    % Direct evaluation at scattered samples AND the largest reconstructed peak.
    [~,peak]=max(abs(period(:,j)-m.mean_ug(j)));
    check=unique([round(linspace(0,N-1,min(N,17)))'; peak-1]);
    exact=localSines(f,a,p,fs,check,m.mean_ug(j));
    directError(j)=max(abs(exact-period(check+1,j)));
    tolerance=5e-10*max(1,abs(m.mean_ug(j))+sum(abs(a)));
    assert(directError(j)<=tolerance,'Sine/FFT mismatch: check coefficient precision and conventions.');
end

% This period was computed above from numbers only. Repeat it at fitted Fs.
% One common offset per realization preserves relative tone/axis phases.
stream=RandStream('mt19937ar','Seed',c.seed);
error_ug=zeros(ns,3,R); offsets=zeros(R,1); difference=zeros(R,1);
sample=(0:ns-1)';
for r=1:R
    if strcmp(m.phaseMode,'randomCircularShift'), offsets(r)=floor(rand(stream)*N); end
    index=mod(sample+offsets(r),N)+1;
    for j=find(m.selectedMask)
        error_ug(:,j,r)=period(index,j);
        if m.whiteSigma_ug(j)>0
            % Fresh draws at EVERY sample, not a repeated white-noise vector.
            error_ug(:,j,r)=error_ug(:,j,r)+m.whiteSigma_ug(j)*randn(stream,ns,1);
        end
    end
    if r>1, difference(r)=max(abs(error_ug(:,:,r)-error_ug(:,:,1)),[],'all'); end
end
names={'X';'Y';'Z'}; selected=find(m.selectedMask);
out=struct('time_s',sample/fs,'error_sensor_ug',error_ug, ...
    'onePeriod_sensor_ug',period,'modelUsed',m,'Fs_Hz',fs,'period_s',N/fs, ...
    'requestedDuration_s',requested,'actualDuration_s',ns/fs, ...
    'seed',c.seed,'synthesisMethod',c.synthesisMethod);
out.coefficientInfo=table(names(selected),count(selected),3*count(selected)+2, ...
    m.mean_ug(selected)',m.whiteSigma_ug(selected)',directError(selected), ...
    'VariableNames',{'SensorAxis','Tones','CoreCoefficients','Mean_ug','WhiteSigma_ug','DirectSineMaxError_ug'});
out.runInfo=table((1:R)',offsets,difference, ...
    'VariableNames',{'Realization','StartOffset_samples','MaxDifferenceFromRun1_ug'});
fprintf('\nCOEFFICIENT-ONLY FOURIER SYNTHESIS\n');
fprintf('Fs %.12g Hz; period %.12g s (%d samples); %d samples/run = %.12g s.\n',fs,N/fs,N,ns,ns/fs);
fprintf('Time labels run from 0 to %.12g s; each row occupies one 1/Fs interval.\n',out.time_s(end));
fprintf('Output is SENSOR-frame acceleration error [micro-g]; unselected columns are zero.\n');
disp(out.coefficientInfo); disp(out.runInfo);
if strcmp(m.phaseMode,'aligned') && all(m.whiteSigma_ug==0)
    fprintf('Deterministic: changing seed or realization count does not change a history.\n');
elseif all(m.whiteSigma_ug==0)
    fprintf('Random start only: each run shifts the same pattern; each run repeats every N/Fs.\n');
else
    fprintf('The Fourier backbone repeats; fresh white noise varies across samples, cycles and runs.\n');
end
end

function m = localCoefficients(input,c)
required={'Fs','recordSamples','selectedMask','mean_ug','whiteSigma_ug','toneFreq','toneAmp','tonePhase'};
assert(isstruct(input)&&isscalar(input)&&all(isfield(input,required)), ...
    'Use IMU_Results.model or the saved FourierModel from the Fourier package.');
validateattributes(input.Fs,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(input.recordSamples,{'numeric'},{'scalar','real','finite','integer','positive'});
validateattributes(input.mean_ug,{'numeric'},{'real','finite','numel',3});
validateattributes(input.whiteSigma_ug,{'numeric'},{'real','finite','nonnegative','numel',3});
assert(numel(input.selectedMask)==3 && all(ismember(input.selectedMask(:),[0 1])) && any(input.selectedMask(:)));
assert(iscell(input.toneFreq)&&numel(input.toneFreq)==3 && ...
       iscell(input.toneAmp)&&numel(input.toneAmp)==3 && iscell(input.tonePhase)&&numel(input.tonePhase)==3);
assert(isscalar(c.maxTones)&&isreal(c.maxTones)&&c.maxTones>=0 && ...
    (c.maxTones==Inf || (isfinite(c.maxTones)&&c.maxTones==floor(c.maxTones))));
assert(ismember(c.toneSelection,{'energy','lowFrequency'}));
mode=c.phaseMode;
if strcmp(mode,'model')
    mode='aligned'; if isfield(input,'phaseMode'), mode=input.phaseMode; end
end
assert(ismember(mode,{'aligned','randomCircularShift'}));
% Copy only the runtime values. No fittedHistory, fullFFT or measured rows.
m=struct('mode','phase_preserved_fourier','Fs',double(input.Fs), ...
    'recordSamples',double(input.recordSamples),'period_s',input.recordSamples/input.Fs, ...
    'selectedMask',logical(reshape(input.selectedMask,1,3)),'phaseMode',mode, ...
    'mean_ug',reshape(input.mean_ug,1,3),'whiteSigma_ug',reshape(input.whiteSigma_ug,1,3), ...
    'toneFreq',{cell(1,3)},'toneAmp',{cell(1,3)},'tonePhase',{cell(1,3)},'toneBin',{cell(1,3)});
if ~isempty(c.whiteSigmaOverride_ug)
    w=c.whiteSigmaOverride_ug;
    validateattributes(w,{'numeric'},{'real','finite','nonnegative'});
    assert(isscalar(w)||numel(w)==3,'White override must be a scalar or XYZ vector.');
    if isscalar(w), w=repmat(w,1,3); end
    m.whiteSigma_ug=reshape(w,1,3);
end
m.mean_ug(~m.selectedMask)=0; m.whiteSigma_ug(~m.selectedMask)=0;
for j=find(m.selectedMask)
    f=double(input.toneFreq{j}(:)); a=double(input.toneAmp{j}(:)); p=double(input.tonePhase{j}(:));
    assert(numel(f)==numel(a)&&numel(a)==numel(p),'Tone-array lengths must match.');
    assert(isreal(f)&&isreal(a)&&isreal(p)&&all(isfinite([f;a;p]))&&all(a>=0));
    bin=f*m.recordSamples/m.Fs; b=round(bin);
    assert(all(abs(bin-b)<1e-7) && all(b>=1 & b<=floor(m.recordSamples/2)) && ...
        numel(unique(b))==numel(b),'Use full-precision, unique FFT-grid frequencies from this package.');
    if strcmp(c.toneSelection,'energy')
        power=a.^2/2;
        if mod(m.recordSamples,2)==0
            nyquist=b==m.recordSamples/2; power(nyquist)=(a(nyquist).*sin(p(nyquist))).^2;
        end
        [~,order]=sort(power,'descend');
    else
        [~,order]=sort(f);
    end
    keep=order(1:min(numel(f),c.maxTones)); [~,ascending]=sort(f(keep)); keep=keep(ascending);
    m.toneFreq{j}=f(keep); m.toneAmp{j}=a(keep); m.tonePhase{j}=p(keep); m.toneBin{j}=b(keep);
end
end

function y = localSines(f,a,p,fs,samples,mu)
% Literal C++ sine formula, with bounded temporary matrices for MATLAB speed.
y=mu*ones(numel(samples),1);
for first=1:4096:numel(samples)
    rows=first:min(first+4095,numel(samples)); t=samples(rows)/fs;
    subtotal=zeros(numel(rows),1);
    for k=1:64:numel(f)
        tones=k:min(k+63,numel(f));
        subtotal=subtotal+sin((2*pi*t)*f(tones)'+p(tones)')*a(tones);
    end
    y(rows)=mu+subtotal;
end
end

function summary = localCompare(out,reference)
summary=table;
if isempty(reference)
    fprintf('No measured rows used or needed. Fit-record residual comparison skipped.\n');
    return
end
N=out.modelUsed.recordSamples; axes=find(out.modelUsed.selectedMask); names={'X';'Y';'Z'};
assert(isnumeric(reference)&&isreal(reference)&&isequal(size(reference),[N 3])&&all(isfinite(reference(:))), ...
    'The optional comparison must be IMU_Results.train, already converted to SENSOR error [ug].');
rmse=zeros(numel(axes),1); maximum=rmse;
for k=1:numel(axes)
    j=axes(k); residual=out.onePeriod_sensor_ug(:,j)-reference(:,j);
    rmse(k)=sqrt(mean(residual.^2)); maximum(k)=max(abs(residual));
end
summary=table(names(axes),rmse,maximum,'VariableNames',{'SensorAxis','ToneOnlyFitRMSE_ug','ToneOnlyFitMaxError_ug'});
fprintf('Optional FIT-record comparison: aligned coefficients, without fresh white or start shift.\n');
fprintf('This measures reconstruction of the fitted record, not independent predictive accuracy.\n');
disp(summary);
end

function localPlot(out,c,reference)
names={'X','Y','Z'}; m=out.modelUsed; selected=find(m.selectedMask); j=selected(1);
if ~isempty(c.plotAxis)
    j=find(strcmpi(c.plotAxis,names),1); assert(~isempty(j)&&m.selectedMask(j),'Choose a selected SENSOR axis.');
end
t=out.time_s; ns=numel(t); N=m.recordSamples; R=height(out.runInfo); y=out.error_sensor_ug(:,j,1);
fig=figure('Name','Standalone Fourier time series','NumberTitle','off', ...
    'Visible',c.figureVisible,'Position',[70 70 1450 850]);
tiles=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(tiles); plot(ax,t,y,'Color',[.75 .1 .12]); hold(ax,'on');
for q=1:min(20,floor(out.actualDuration_s/out.period_s))
    if q*out.period_s<t(end), xline(ax,q*out.period_s,':','HandleVisibility','off'); end
end
title(ax,'Generated run 1; dotted lines mark N/Fs periods'); xlabel(ax,'Time [s]'); ylabel(ax,'Sensor error [ug]'); grid(ax,'on');

ax=nexttile(tiles); available=min(N,ns); [~,peak]=max(abs(y(1:available)-m.mean_ug(j)));
idx=max(1,peak-c.zoomHalfWidth_samples):min(ns,peak+c.zoomHalfWidth_samples);
plot(ax,t(idx),y(idx),'-o','MarkerSize',4,'Color',[.75 .1 .12]);
title(ax,'Largest first-cycle peak: every sample marked'); xlabel(ax,'Time [s]'); ylabel(ax,'Sensor error [ug]'); grid(ax,'on');

ax=nexttile(tiles);
if R>1
    idx=1:min(ns,N); hold(ax,'on');
    for r=1:R, plot(ax,t(idx),out.error_sensor_ug(idx,j,r),'DisplayName',sprintf('Run %d',r)); end
    title(ax,'Realizations: identical runs lie on top of each other'); xlabel(ax,'Time [s]'); ylabel(ax,'Sensor error [ug]');
    if R<=10, legend(ax,'show','Location','best'); end
else
    histogram(ax,y,80,'Normalization','probability');
    title(ax,'Generated amplitude distribution: run 1'); xlabel(ax,'Sensor error [ug]'); ylabel(ax,'Probability/bin');
end
grid(ax,'on');

ax=nexttile(tiles);
if R>1
    hold(ax,'on');
    for r=2:R, plot(ax,t,out.error_sensor_ug(:,j,r)-y); end
    title(ax,'Each run minus run 1; zero means identical'); xlabel(ax,'Time [s]'); ylabel(ax,'Difference [ug]');
elseif ns>N
    idx=(1:min(N,ns-N))'; difference=y(N+idx)-y(idx);
    plot(ax,(idx-1)/m.Fs,difference); title(ax,'Cycle 2 minus cycle 1: run 1');
    xlabel(ax,'Time within cycle [s]'); ylabel(ax,'Difference [ug]');
else
    text(ax,.05,.5,'Use >1 period or nRealizations=10 to display differences.','Units','normalized');
    title(ax,'No second cycle/run requested');
end
grid(ax,'on'); title(tiles,sprintf('Coefficient-only synthesis | Sensor %s | T = %.6g s | %s',names{j},out.period_s,m.phaseMode));

if ~isempty(reference)
    fig=figure('Name','Standalone reconstruction residual','NumberTitle','off', ...
        'Visible',c.figureVisible,'Position',[100 100 1400 750]);
    tiles=tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
    tt=(0:N-1)'/m.Fs; reconstructed=out.onePeriod_sensor_ug(:,j);
    residual=reconstructed-reference(:,j);
    ax=nexttile(tiles); plot(ax,tt,reference(:,j),'k','DisplayName','Measured fit record'); hold(ax,'on');
    plot(ax,tt,reconstructed,'Color',[.75 .1 .12],'DisplayName','Regenerated from coefficients');
    title(ax,'Aligned tone-only comparison; fresh white and random offset excluded');
    xlabel(ax,'Time [s]'); ylabel(ax,'Sensor error [ug]'); legend(ax,'show'); grid(ax,'on');
    ax=nexttile(tiles); plot(ax,tt,residual); grid(ax,'on');
    title(ax,sprintf('Reconstructed minus measured | RMSE %.6g ug | max abs %.6g ug', ...
        sqrt(mean(residual.^2)),max(abs(residual))));
    xlabel(ax,'Time [s]'); ylabel(ax,'Residual [ug]');
    title(tiles,'Fit-record reconstruction check: full Fourier agreement may be only round-off');
end
end

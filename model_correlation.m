%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% GYRO AR NOISE MODEL VALIDATION
%
% PURPOSE
% -------
% Validate a test-derived autoregressive (AR) gyro noise model against
% measured test data, using both frequency-domain and time-domain
% statistical measures.
%
% PRIMARY QUESTIONS ANSWERED
% --------------------------
% 1. Does the AR model reproduce the measured PSD?
% 2. Does it reproduce the measured tonal content?
% 3. Does it reproduce the measured temporal correlation?
% 4. Does it reproduce the measured behavior across averaging time?
% 5. Does applying the inverse AR relationship leave approximately
%    white innovations?
% 6. After implementation in the simulation, how does the sensor output
%    differ between:
%       A) conventional RMS-scaled white noise
%       B) test-derived AR / tonal noise?
%
%
% REQUIRED MATLAB VARIABLES
% -------------------------
% fs            : Sample rate [Hz] of testResidual
% testResidual  : Exact residual used to identify the AR model
% aNoise        : AR denominator coefficients from aryule()
% bNoise        : sqrt(noiseVar) from aryule()
%
% Example identification:
%
%   [aNoise, noiseVar] = aryule(testResidual, noiseOrder);
%   bNoise = sqrt(noiseVar);
%
%
% OPTIONAL VARIABLES
% ------------------
% toneFreqHz
% toneAmp
% tonePhaseRad
% testSignalWithTones
%
% These are only required if tones were modeled separately from the AR
% residual.
%
%
% NOTES
% -----
% - This script deliberately does NOT perform an AR-order sweep.
% - The selected AR order is assumed to have already been chosen by
%   increasing order until sufficient spectral agreement was obtained.
% - pwelch() and xcorr() require Signal Processing Toolbox, which is
%   already typically available if aryule() is being used.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clc;
close all;


%% ========================================================================
%  1. USER INPUTS AND ANALYSIS SETTINGS
%
%  WHAT GOES IN:
%  -------------
%  The measured residual and final AR coefficients produced by the model
%  identification process.
%
%  WHAT WE LEARN:
%  --------------
%  Nothing is evaluated here. This section simply establishes all settings
%  in one location so that the remainder of the script is repeatable.
%
%  If these variables already exist in the workspace, this script will use
%  them rather than overwrite them.
% =========================================================================


% -------------------------------------------------------------------------
% REQUIRED INPUTS
% -------------------------------------------------------------------------

if ~exist('fs','var')
    fs = [];
end

if ~exist('testResidual','var')
    testResidual = [];
end

if ~exist('aNoise','var')
    aNoise = [];
end

if ~exist('bNoise','var')
    bNoise = [];
end


% -------------------------------------------------------------------------
% OPTIONAL EXPLICIT TONE MODEL
%
% Set addExplicitToneModel = true ONLY if the AR model represents the
% residual AFTER deterministic tones were removed.
%
% In that case:
%
%   testSignalWithTones = de-biased measured test signal WITH tones
%
% and
%
%   full model = AR realization + explicit tone model
%
% If your AR model itself contains the spectral peaks/tones, leave this
% false to avoid double-counting tones.
% -------------------------------------------------------------------------

if ~exist('addExplicitToneModel','var')
    addExplicitToneModel = false;
end

if ~exist('toneFreqHz','var')
    toneFreqHz = [];
end

if ~exist('toneAmp','var')
    toneAmp = [];
end

if ~exist('tonePhaseRad','var')
    tonePhaseRad = [];
end

if ~exist('testSignalWithTones','var')
    testSignalWithTones = [];
end


% -------------------------------------------------------------------------
% GENERAL ANALYSIS SETTINGS
% -------------------------------------------------------------------------

if ~exist('rngSeed','var')
    rngSeed = 1;
end

if ~exist('maxLagSec','var')
    maxLagSec = 2.0;
end

if ~exist('toneSearchHalfWidthHz','var')
    toneSearchHalfWidthHz = 0.5;
end

if ~exist('doAllanDeviation','var')
    doAllanDeviation = true;
end

if ~exist('saveResults','var')
    saveResults = false;
end

if ~exist('resultsFileName','var')
    resultsFileName = 'gyro_AR_validation_results.mat';
end


% -------------------------------------------------------------------------
% PSD SETTINGS
%
% Leaving these as [] reproduces MATLAB's normal pwelch defaults:
%
%   [Pxx,f] = pwelch(x,[],[],[],fs)
%
% This is intentionally consistent with the PSD workflow already used
% during model development.
% -------------------------------------------------------------------------

if ~exist('welchWindow','var')
    welchWindow = [];
end

if ~exist('welchNoverlap','var')
    welchNoverlap = [];
end

if ~exist('welchNfft','var')
    welchNfft = [];
end


% -------------------------------------------------------------------------
% PLOT LABELS
% -------------------------------------------------------------------------

if ~exist('signalUnit','var')
    signalUnit = 'rad/s';
end

if ~exist('signalName','var')
    signalName = 'Gyro noise';
end


%% ========================================================================
%  2. INPUT CHECKS AND AR MODEL GENERATION
%
%  WHAT GOES IN:
%  -------------
%  testResidual, fs, aNoise, and bNoise.
%
%  WHAT WE DO:
%  -----------
%  Drive the identified AR filter with unit Gaussian noise:
%
%                bNoise
%       H(z) = -----------
%                aNoise
%
%  A burn-in portion is generated and discarded so that the filter startup
%  transient is not included in the validation data.
%
%  WHAT WE LEARN:
%  --------------
%  This produces the stochastic AR realization that all subsequent
%  validation analyses will compare against the measured residual.
% =========================================================================


% Required input checks
if isempty(fs)
    error('fs must be defined before running this script.');
end

if isempty(testResidual)
    error('testResidual must be defined before running this script.');
end

if isempty(aNoise)
    error('aNoise must be defined before running this script.');
end

if isempty(bNoise)
    error('bNoise must be defined before running this script.');
end

if ~isscalar(bNoise)
    error('bNoise is expected to be a scalar equal to sqrt(noiseVar).');
end


% Force vectors into consistent orientation
testResidual = testResidual(:);
aNoise       = aNoise(:).';

N = length(testResidual);

ARorder = length(aNoise) - 1;


% Default analysis frequency range
if ~exist('analysisFreqRangeHz','var') || isempty(analysisFreqRangeHz)
    analysisFreqRangeHz = [0 fs/2];
end

analysisFreqRangeHz(1) = max(0,analysisFreqRangeHz(1));
analysisFreqRangeHz(2) = min(fs/2,analysisFreqRangeHz(2));


% Default burn-in
if ~exist('burnInSamples','var') || isempty(burnInSamples)

    burnInSamples = max(10*ARorder, round(5*fs));

end


% -------------------------------------------------------------------------
% Check AR stability
% -------------------------------------------------------------------------

if ARorder > 0

    arPoles = roots(aNoise);
    maxPoleMagnitude = max(abs(arPoles));

else

    arPoles = [];
    maxPoleMagnitude = 0;

end

if maxPoleMagnitude >= 1

    warning(['AR filter contains a pole on or outside the unit circle. ' ...
             'Generated output may be unstable.']);

end


% -------------------------------------------------------------------------
% Generate independent unit-Gaussian excitation
% -------------------------------------------------------------------------

rng(rngSeed,'twister');

unitGaussian = randn(N + burnInSamples,1);


% -------------------------------------------------------------------------
% Generate AR realization
% -------------------------------------------------------------------------

arFull = filter(bNoise,aNoise,unitGaussian);

arModel = arFull(burnInSamples+1:end);


% Remove any tiny numerical mean difference for comparison
testResidualZeroMean = testResidual - mean(testResidual);
arModelZeroMean      = arModel      - mean(arModel);


fprintf('\n============================================================\n');
fprintf('GYRO AR MODEL VALIDATION\n');
fprintf('============================================================\n');
fprintf('Sample rate             : %.6f Hz\n',fs);
fprintf('Number of test samples  : %d\n',N);
fprintf('AR order                : %d\n',ARorder);
fprintf('Burn-in samples         : %d\n',burnInSamples);
fprintf('Maximum pole magnitude  : %.6f\n',maxPoleMagnitude);
fprintf('============================================================\n\n');


results = struct;

results.fs               = fs;
results.N                = N;
results.ARorder          = ARorder;
results.burnInSamples    = burnInSamples;
results.maxPoleMagnitude = maxPoleMagnitude;


%% ========================================================================
%  3. TEST RESIDUAL VS AR MODEL PSD
%
%  WHAT GOES IN:
%  -------------
%  - Measured test residual
%  - AR-generated realization
%
%  WHAT WE DO:
%  -----------
%  Compute both PSDs using IDENTICAL Welch settings.
%
%  WHAT WE LEARN:
%  --------------
%  This is the primary frequency-domain validation.
%
%  Good agreement indicates that the identified AR process reproduces the
%  distribution of noise power across frequency rather than merely matching
%  a single RMS value.
%
%  QUANTITATIVE OUTPUTS:
%  ---------------------
%  - PSD RMSE [dB]
%  - PSD MAE [dB]
%  - Relative PSD L2 error
%  - Time-domain RMS
%  - PSD-integrated RMS
% =========================================================================


[Ptest,fTest] = pwelch(testResidualZeroMean, ...
                       welchWindow, ...
                       welchNoverlap, ...
                       welchNfft, ...
                       fs);

[Par,fAR] = pwelch(arModelZeroMean, ...
                   welchWindow, ...
                   welchNoverlap, ...
                   welchNfft, ...
                   fs);


% Interpolate AR PSD onto test frequency bins if necessary
if length(fAR) ~= length(fTest) || any(abs(fAR-fTest) > 1e-12)

    ParCommon = interp1(fAR,Par,fTest,'linear','extrap');

else

    ParCommon = Par;

end


% Frequency range used for quantitative comparison
freqMask = fTest >= analysisFreqRangeHz(1) & ...
           fTest <= analysisFreqRangeHz(2);


Ptest_dB = 10*log10(max(Ptest,realmin));
Par_dB   = 10*log10(max(ParCommon,realmin));


% -------------------------------------------------------------------------
% Quantitative PSD metrics
% -------------------------------------------------------------------------

psdDifference_dB = Par_dB(freqMask) - Ptest_dB(freqMask);

psdRMSE_dB = sqrt(mean(psdDifference_dB.^2));

psdMAE_dB = mean(abs(psdDifference_dB));

psdRelativeL2 = norm(ParCommon(freqMask) - Ptest(freqMask)) / ...
                max(norm(Ptest(freqMask)),eps);


% -------------------------------------------------------------------------
% RMS calculated directly in the time domain
% -------------------------------------------------------------------------

testRMS_time = sqrt(mean(testResidualZeroMean.^2));
arRMS_time   = sqrt(mean(arModelZeroMean.^2));

rmsErrorPercent = 100*(arRMS_time-testRMS_time) / ...
                  max(abs(testRMS_time),eps);


% -------------------------------------------------------------------------
% RMS calculated by integrating PSD
% -------------------------------------------------------------------------

testRMS_PSD = sqrt(trapz(fTest,Ptest));
arRMS_PSD   = sqrt(trapz(fTest,ParCommon));


fprintf('--- PSD VALIDATION -----------------------------------------\n');
fprintf('PSD RMSE                     : %.6f dB\n',psdRMSE_dB);
fprintf('PSD MAE                      : %.6f dB\n',psdMAE_dB);
fprintf('Relative PSD L2 error        : %.6f\n',psdRelativeL2);
fprintf('\n');
fprintf('Test RMS, time domain        : %.10g %s\n', ...
        testRMS_time,signalUnit);
fprintf('AR RMS, time domain          : %.10g %s\n', ...
        arRMS_time,signalUnit);
fprintf('RMS percent error            : %.4f %%\n',rmsErrorPercent);
fprintf('\n');
fprintf('Test RMS, PSD integration    : %.10g %s\n', ...
        testRMS_PSD,signalUnit);
fprintf('AR RMS, PSD integration      : %.10g %s\n', ...
        arRMS_PSD,signalUnit);
fprintf('------------------------------------------------------------\n\n');


% -------------------------------------------------------------------------
% PSD figure
% -------------------------------------------------------------------------

figure('Name','Residual vs AR PSD');

semilogy(fTest,Ptest,'LineWidth',1.4);
hold on;

semilogy(fTest,ParCommon,'LineWidth',1.4);

grid on;

xlabel('Frequency [Hz]');
ylabel(['PSD [(' signalUnit ')^2/Hz]']);

title('Test Residual vs AR Model PSD');

legend('Test Residual','AR Model','Location','best');

xlim(analysisFreqRangeHz);


% Store results
results.PSD.f              = fTest;
results.PSD.test           = Ptest;
results.PSD.AR             = ParCommon;
results.PSD.RMSE_dB        = psdRMSE_dB;
results.PSD.MAE_dB         = psdMAE_dB;
results.PSD.relativeL2     = psdRelativeL2;

results.RMS.test_time      = testRMS_time;
results.RMS.AR_time        = arRMS_time;
results.RMS.errorPercent   = rmsErrorPercent;
results.RMS.test_PSD       = testRMS_PSD;
results.RMS.AR_PSD         = arRMS_PSD;


%% ========================================================================
%  4. QUANTITATIVE TONE AGREEMENT
%
%  WHAT GOES IN:
%  -------------
%  Expected tone frequencies in:
%
%       toneFreqHz
%
%  Two operating modes are supported.
%
%
%  MODE A: AR MODEL ITSELF CONTAINS THE TONES
%  -------------------------------------------
%
%       addExplicitToneModel = false
%
%  Tone metrics are calculated directly between:
%
%       testResidual  vs  arModel
%
%
%  MODE B: TONES WERE REMOVED BEFORE AR IDENTIFICATION
%  ---------------------------------------------------
%
%       addExplicitToneModel = true
%
%  The comparison becomes:
%
%       testSignalWithTones
%
%                 versus
%
%       arModel + explicit tone model
%
%
%  WHAT WE LEARN:
%  --------------
%  Rather than relying only on visual PSD agreement, this section measures:
%
%  - Tone frequency error [Hz]
%  - Tone PSD peak error [dB]
%  - Integrated bandpower error [%]
%
%  Integrated power around a tone is generally more robust than comparing
%  a single Welch PSD bin.
% =========================================================================


toneValidationTest  = testResidualZeroMean;
toneValidationModel = arModelZeroMean;


if addExplicitToneModel

    if isempty(toneFreqHz) || isempty(toneAmp) || isempty(tonePhaseRad)

        error(['addExplicitToneModel=true requires toneFreqHz, ' ...
               'toneAmp, and tonePhaseRad.']);

    end

    if isempty(testSignalWithTones)

        error(['addExplicitToneModel=true also requires ' ...
               'testSignalWithTones.']);

    end

    if length(toneFreqHz) ~= length(toneAmp) || ...
       length(toneFreqHz) ~= length(tonePhaseRad)

        error('toneFreqHz, toneAmp, and tonePhaseRad must have equal length.');

    end

    testSignalWithTones = testSignalWithTones(:);

    if length(testSignalWithTones) ~= N

        error(['testSignalWithTones must correspond to the same region ' ...
               'and contain the same number of samples as testResidual.']);

    end


    % Build explicit tone model
    tTest = (0:N-1)'/fs;

    explicitToneModel = zeros(N,1);

    for iTone = 1:length(toneFreqHz)

        explicitToneModel = explicitToneModel + ...
            toneAmp(iTone) .* ...
            sin(2*pi*toneFreqHz(iTone).*tTest + tonePhaseRad(iTone));

    end


    toneValidationTest = testSignalWithTones - mean(testSignalWithTones);

    toneValidationModel = arModelZeroMean + explicitToneModel;


    % Generate full-noise PSD comparison
    [PtoneTest,fToneTest] = pwelch(toneValidationTest, ...
                                   welchWindow, ...
                                   welchNoverlap, ...
                                   welchNfft, ...
                                   fs);

    [PtoneModel,fToneModel] = pwelch(toneValidationModel, ...
                                     welchWindow, ...
                                     welchNoverlap, ...
                                     welchNfft, ...
                                     fs);

    PtoneModelCommon = interp1(fToneModel, ...
                               PtoneModel, ...
                               fToneTest, ...
                               'linear', ...
                               'extrap');


    figure('Name','Full Noise Model Tone Validation');

    semilogy(fToneTest,PtoneTest,'LineWidth',1.4);
    hold on;

    semilogy(fToneTest,PtoneModelCommon,'LineWidth',1.4);

    grid on;

    xlabel('Frequency [Hz]');
    ylabel(['PSD [(' signalUnit ')^2/Hz]']);

    title('Test Noise vs AR + Explicit Tone Model');

    legend('Test Noise','AR + Tone Model','Location','best');

    xlim(analysisFreqRangeHz);


else

    fToneTest        = fTest;
    PtoneTest        = Ptest;
    PtoneModelCommon = ParCommon;

end


% -------------------------------------------------------------------------
% Calculate tone metrics
% -------------------------------------------------------------------------

if ~isempty(toneFreqHz)

    toneMetrics = calculateToneMetrics( ...
        fToneTest, ...
        PtoneTest, ...
        PtoneModelCommon, ...
        toneFreqHz, ...
        toneSearchHalfWidthHz);


    fprintf('--- TONE VALIDATION ----------------------------------------\n');

    if addExplicitToneModel
        fprintf('Reference  = measured test signal containing tones\n');
        fprintf('Comparison = AR model + explicit tone model\n\n');
    else
        fprintf('Reference  = measured test residual\n');
        fprintf('Comparison = AR model\n\n');
    end

    disp(toneMetrics);

    fprintf('------------------------------------------------------------\n\n');


    results.toneMetrics = toneMetrics;

else

    fprintf(['Tone metrics skipped because toneFreqHz is empty.\n' ...
             'Populate toneFreqHz to enable tone-specific metrics.\n\n']);

    results.toneMetrics = table;

end


%% ========================================================================
%  5. TEST RESIDUAL VS AR MODEL AUTOCORRELATION
%
%  WHAT GOES IN:
%  -------------
%  - Test residual
%  - AR-generated realization
%
%  WHAT WE DO:
%  -----------
%  Calculate normalized autocorrelation as a function of time lag.
%
%  WHAT WE LEARN:
%  --------------
%  PSD agreement demonstrates similar frequency-domain energy.
%
%  Autocorrelation tests whether the AR model also reproduces the temporal
%  memory of the measured process.
%
%  A white-noise process should have approximately zero correlation away
%  from zero lag, while a colored process can retain significant
%  correlation across many samples.
%
%  QUANTITATIVE OUTPUTS:
%  ---------------------
%  - Autocorrelation RMSE
%  - Relative autocorrelation L2 error
%  - Off-zero-lag autocorrelation RMSE
% =========================================================================


maxLagSamples = min(round(maxLagSec*fs),N-1);


[Rtest,lags] = xcorr(testResidualZeroMean, ...
                     maxLagSamples, ...
                     'coeff');

[Rar,~] = xcorr(arModelZeroMean, ...
                maxLagSamples, ...
                'coeff');


lagSec = lags/fs;


acfDifference = Rar - Rtest;

acfRMSE = sqrt(mean(acfDifference.^2));

acfRelativeL2 = norm(acfDifference) / ...
                max(norm(Rtest),eps);


offZeroMask = lags ~= 0;

acfRMSE_offZero = sqrt(mean(acfDifference(offZeroMask).^2));


fprintf('--- AUTOCORRELATION VALIDATION -----------------------------\n');
fprintf('ACF RMSE                     : %.8f\n',acfRMSE);
fprintf('Relative ACF L2 error        : %.8f\n',acfRelativeL2);
fprintf('Off-zero-lag ACF RMSE        : %.8f\n',acfRMSE_offZero);
fprintf('------------------------------------------------------------\n\n');


figure('Name','Residual vs AR Autocorrelation');

plot(lagSec,Rtest,'LineWidth',1.4);
hold on;

plot(lagSec,Rar,'LineWidth',1.4);

grid on;

xlabel('Lag [s]');
ylabel('Normalized Autocorrelation');

title('Test Residual vs AR Model Autocorrelation');

legend('Test Residual','AR Model','Location','best');


results.ACF.lagSec          = lagSec;
results.ACF.test            = Rtest;
results.ACF.AR              = Rar;
results.ACF.RMSE            = acfRMSE;
results.ACF.relativeL2      = acfRelativeL2;
results.ACF.RMSE_offZero    = acfRMSE_offZero;


%% ========================================================================
%  6. L2 DEVIATION METRICS
%
%  WHAT GOES IN:
%  -------------
%  The measured residual and an independently generated AR realization.
%
%  WHAT WE DO:
%  -----------
%  Calculate several normalized L2 errors.
%
%  IMPORTANT INTERPRETATION:
%  -------------------------
%  A direct sample-by-sample L2 difference between TWO INDEPENDENT
%  stochastic realizations is NOT expected to approach zero, even if both
%  sequences represent exactly the same stochastic process.
%
%  Therefore:
%
%  Direct time-history L2 = descriptive only.
%
%  PSD and autocorrelation L2 metrics are substantially more meaningful
%  model-validation quantities because they compare statistical
%  characteristics rather than random sample paths.
%
%  WHAT WE LEARN:
%  --------------
%  This provides explicit norm-based measures that can be quoted alongside
%  visual comparisons.
% =========================================================================


timeDomainRelativeL2 = ...
    norm(arModelZeroMean - testResidualZeroMean) / ...
    max(norm(testResidualZeroMean),eps);


fprintf('--- L2 DEVIATION METRICS -----------------------------------\n');
fprintf('Direct time-history relative L2 : %.8f\n', ...
        timeDomainRelativeL2);
fprintf('PSD relative L2                 : %.8f\n', ...
        psdRelativeL2);
fprintf('Autocorrelation relative L2     : %.8f\n', ...
        acfRelativeL2);
fprintf('\n');
fprintf(['NOTE: The direct time-history value is descriptive only,\n' ...
         'because the two stochastic realizations are independent.\n']);
fprintf('------------------------------------------------------------\n\n');


results.L2.timeHistoryRelative = timeDomainRelativeL2;
results.L2.PSDrelative         = psdRelativeL2;
results.L2.ACFrelative         = acfRelativeL2;


%% ========================================================================
%  7. ALLAN DEVIATION COMPARISON
%
%  WHAT GOES IN:
%  -------------
%  - Test residual
%  - AR model realization
%
%  WHAT WE DO:
%  -----------
%  Calculate overlapping Allan deviation over logarithmically spaced
%  averaging intervals.
%
%  WHAT WE LEARN:
%  --------------
%  PSD describes frequency-domain power.
%
%  Allan deviation provides another view of how the noise behaves as the
%  observation / averaging time changes.
%
%  The purpose here is NOT necessarily to identify every classical gyro
%  noise coefficient.
%
%  Instead, the validation question is:
%
%      "Does the AR model reproduce the measured Allan-deviation behavior
%       across the time scales supported by the available test record?"
%
%  QUANTITATIVE OUTPUT:
%  --------------------
%  Allan deviation RMSE expressed in dB.
% =========================================================================


if doAllanDeviation

    maxAllanCluster = floor(N/4);

    if maxAllanCluster >= 2

        nAllanPoints = min(40,maxAllanCluster);

        allanClusterSizes = unique(round(logspace( ...
            0, ...
            log10(maxAllanCluster), ...
            nAllanPoints)));

        allanClusterSizes = allanClusterSizes( ...
            2*allanClusterSizes < N);


        [tauTest,allanTest] = overlappingAllanDeviation( ...
            testResidualZeroMean, ...
            fs, ...
            allanClusterSizes);

        [tauAR,allanAR] = overlappingAllanDeviation( ...
            arModelZeroMean, ...
            fs, ...
            allanClusterSizes);


        validAllan = isfinite(allanTest) & ...
                     isfinite(allanAR)   & ...
                     allanTest > 0      & ...
                     allanAR > 0;


        allanTest_dB = 20*log10(allanTest(validAllan));
        allanAR_dB   = 20*log10(allanAR(validAllan));

        allanRMSE_dB = sqrt(mean((allanAR_dB-allanTest_dB).^2));


        fprintf('--- ALLAN DEVIATION VALIDATION -----------------------------\n');
        fprintf('Allan deviation RMSE         : %.6f dB\n',allanRMSE_dB);
        fprintf('------------------------------------------------------------\n\n');


        figure('Name','Residual vs AR Allan Deviation');

        loglog(tauTest,allanTest,'LineWidth',1.4);
        hold on;

        loglog(tauAR,allanAR,'LineWidth',1.4);

        grid on;

        xlabel('Averaging Time, \tau [s]');
        ylabel(['Allan Deviation [' signalUnit ']']);

        title('Test Residual vs AR Model Allan Deviation');

        legend('Test Residual','AR Model','Location','best');


        results.Allan.tau        = tauTest;
        results.Allan.test       = allanTest;
        results.Allan.AR         = allanAR;
        results.Allan.RMSE_dB    = allanRMSE_dB;

    else

        warning('Test record is too short for useful Allan deviation.');

    end

end


%% ========================================================================
%  8. AR INNOVATION WHITENESS
%
%  WHAT GOES IN:
%  -------------
%  The ORIGINAL measured test residual and identified AR coefficients.
%
%  For the fitted AR process:
%
%       x[k] + a1*x[k-1] + ... + ap*x[k-p] = e[k]
%
%  Applying A(z) to the residual produces the estimated innovation e[k].
%
%
%  WHAT WE LEARN:
%  --------------
%  If the AR model has successfully captured the predictable temporal
%  correlation in the measured residual, the remaining innovations should
%  be substantially closer to white noise.
%
%  The comparison therefore asks:
%
%      Residual = colored?
%
%      Innovation = approximately white?
%
%
%  METRICS:
%  --------
%  1. Spectral flatness
%
%       1.0 -> perfectly flat spectrum
%       smaller -> increasingly colored spectrum
%
%  2. RMS off-zero autocorrelation
%
%  3. Maximum absolute off-zero autocorrelation
%
%  4. Innovation variance vs the expected aryule innovation variance
% =========================================================================


innovationFull = filter(aNoise,1,testResidualZeroMean);


% Initial values do not possess the preceding history assumed by the AR
% equation, so discard at least one full AR-order worth of samples.
innovationDiscardSamples = max(ARorder,1);

innovation = innovationFull(innovationDiscardSamples+1:end);

innovation = innovation - mean(innovation);


% -------------------------------------------------------------------------
% Residual and innovation PSD
% -------------------------------------------------------------------------

[Pres,fResidualWhite] = pwelch(testResidualZeroMean, ...
                               welchWindow, ...
                               welchNoverlap, ...
                               welchNfft, ...
                               fs);

[Pinnovation,fInnovation] = pwelch(innovation, ...
                                   welchWindow, ...
                                   welchNoverlap, ...
                                   welchNfft, ...
                                   fs);


PinnovationCommon = interp1(fInnovation, ...
                            Pinnovation, ...
                            fResidualWhite, ...
                            'linear', ...
                            'extrap');


whiteFreqMask = fResidualWhite >= analysisFreqRangeHz(1) & ...
                fResidualWhite <= analysisFreqRangeHz(2) & ...
                fResidualWhite > 0;


% -------------------------------------------------------------------------
% Spectral flatness
% -------------------------------------------------------------------------

residualSpectralFlatness = spectralFlatness( ...
    Pres(whiteFreqMask));

innovationSpectralFlatness = spectralFlatness( ...
    PinnovationCommon(whiteFreqMask));


% Normalize PSDs by mean band level to emphasize shape rather than
% absolute power.
PresNormalized = Pres / mean(Pres(whiteFreqMask));

PinnovationNormalized = ...
    PinnovationCommon / mean(PinnovationCommon(whiteFreqMask));


% -------------------------------------------------------------------------
% Residual and innovation autocorrelation
% -------------------------------------------------------------------------

whiteMaxLagSamples = min(maxLagSamples,length(innovation)-1);


[RresWhite,lagsWhite] = xcorr(testResidualZeroMean, ...
                              whiteMaxLagSamples, ...
                              'coeff');

[Rinnovation,~] = xcorr(innovation, ...
                        whiteMaxLagSamples, ...
                        'coeff');


offZeroWhite = lagsWhite ~= 0;


residualACFrms = sqrt(mean(RresWhite(offZeroWhite).^2));

innovationACFrms = sqrt(mean(Rinnovation(offZeroWhite).^2));


residualACFmax = max(abs(RresWhite(offZeroWhite)));

innovationACFmax = max(abs(Rinnovation(offZeroWhite)));


% Approximate 95% correlation limits expected for an uncorrelated sequence
whiteConfidence95 = 1.96/sqrt(length(innovation));


% -------------------------------------------------------------------------
% Innovation variance check
% -------------------------------------------------------------------------

innovationVariance = var(innovation,1);

expectedInnovationVariance = bNoise^2;

innovationVarianceErrorPercent = ...
    100*(innovationVariance-expectedInnovationVariance) / ...
    max(expectedInnovationVariance,eps);


fprintf('--- INNOVATION WHITENESS -----------------------------------\n');
fprintf('Residual spectral flatness       : %.8f\n', ...
        residualSpectralFlatness);
fprintf('Innovation spectral flatness     : %.8f\n', ...
        innovationSpectralFlatness);
fprintf('\n');
fprintf('Residual off-zero ACF RMS         : %.8f\n', ...
        residualACFrms);
fprintf('Innovation off-zero ACF RMS       : %.8f\n', ...
        innovationACFrms);
fprintf('\n');
fprintf('Residual maximum |ACF|            : %.8f\n', ...
        residualACFmax);
fprintf('Innovation maximum |ACF|          : %.8f\n', ...
        innovationACFmax);
fprintf('\n');
fprintf('Expected innovation variance      : %.10g\n', ...
        expectedInnovationVariance);
fprintf('Measured innovation variance      : %.10g\n', ...
        innovationVariance);
fprintf('Innovation variance error         : %.4f %%\n', ...
        innovationVarianceErrorPercent);
fprintf('------------------------------------------------------------\n\n');


% -------------------------------------------------------------------------
% Innovation whiteness figure
% -------------------------------------------------------------------------

figure('Name','AR Innovation Whiteness');


subplot(2,1,1);

plot(fResidualWhite, ...
     10*log10(max(PresNormalized,realmin)), ...
     'LineWidth',1.3);

hold on;

plot(fResidualWhite, ...
     10*log10(max(PinnovationNormalized,realmin)), ...
     'LineWidth',1.3);

yline(0,'--');

grid on;

xlabel('Frequency [Hz]');
ylabel('Normalized PSD [dB]');

title('Residual vs AR Innovation Spectral Shape');

legend('Test Residual','AR Innovation','Flat Reference', ...
       'Location','best');

xlim(analysisFreqRangeHz);


subplot(2,1,2);

plot(lagsWhite/fs,RresWhite,'LineWidth',1.3);
hold on;

plot(lagsWhite/fs,Rinnovation,'LineWidth',1.3);

yline( whiteConfidence95,'--');
yline(-whiteConfidence95,'--');

grid on;

xlabel('Lag [s]');
ylabel('Normalized Autocorrelation');

title('Residual vs AR Innovation Autocorrelation');

legend('Test Residual', ...
       'AR Innovation', ...
       'Approx. 95% White-Noise Bound', ...
       'Location','best');


results.Whiteness.residualSpectralFlatness   = ...
    residualSpectralFlatness;

results.Whiteness.innovationSpectralFlatness = ...
    innovationSpectralFlatness;

results.Whiteness.residualACFrms             = residualACFrms;
results.Whiteness.innovationACFrms           = innovationACFrms;

results.Whiteness.residualACFmax             = residualACFmax;
results.Whiteness.innovationACFmax           = innovationACFmax;

results.Whiteness.expectedInnovationVariance = ...
    expectedInnovationVariance;

results.Whiteness.measuredInnovationVariance = ...
    innovationVariance;

results.Whiteness.varianceErrorPercent       = ...
    innovationVarianceErrorPercent;


%% ========================================================================
%  9. RESERVED SIMULATION OUTPUT COMPARISON
%
%  PURPOSE
%  -------
%  This section is intentionally separated from AR MODEL VALIDATION.
%
%  Everything above asks:
%
%       "Is the identified stochastic model representative of the
%        measured gyro noise?"
%
%  This section instead asks:
%
%       "What does the improved model actually change in the simulated
%        sensor measurement?"
%
%
%  REQUIRED SIMULATION DATASETS:
%  -----------------------------
%
%       simWhite_dTheta
%
%           Gyro delta-angle measurement from the simulation using the
%           conventional RMS-scaled white-noise model.
%
%
%       simAR_dTheta
%
%           Gyro delta-angle measurement from the otherwise equivalent
%           simulation using the test-derived AR / tonal model.
%
%
%       fsSim
%
%           Output sample rate of the gyro delta-angle data.
%
%
%  OPTIONAL:
%  ---------
%
%       simWhiteTruth_dTheta
%       simARTruth_dTheta
%
%  If truth / noiseless delta-angle outputs are available, this script
%  additionally forms:
%
%       deltaThetaError = measured deltaTheta - truth deltaTheta
%
%  This is often a cleaner demonstration because actual vehicle motion can
%  dominate the PSD of the full gyro output.
%
%
%  WHAT WE LEARN:
%  --------------
%  White-noise simulation:
%
%       broadband / approximately flat stochastic contribution
%
%  AR / tonal simulation:
%
%       measurement contains spectral structure at frequencies observed
%       during sensor test.
%
%  This demonstrates an effect on the ACTUAL SENSOR OUTPUT rather than
%  merely showing the noise model by itself.
% =========================================================================


% -------------------------------------------------------------------------
% INSERT OR LOAD SIMULATION DATA HERE
%
% Example:
%
%   whiteRun = load('whiteNoiseRun.mat');
%   simWhite_dTheta = whiteRun.deltaTheta;
%
%   arRun = load('ARNoiseRun.mat');
%   simAR_dTheta = arRun.deltaTheta;
%
% -------------------------------------------------------------------------

if ~exist('simWhite_dTheta','var')
    simWhite_dTheta = [];
end

if ~exist('simAR_dTheta','var')
    simAR_dTheta = [];
end

if ~exist('simWhiteTruth_dTheta','var')
    simWhiteTruth_dTheta = [];
end

if ~exist('simARTruth_dTheta','var')
    simARTruth_dTheta = [];
end

if ~exist('fsSim','var')
    fsSim = [];
end

if ~exist('simSignalUnit','var')
    simSignalUnit = 'rad';
end

if ~exist('removeMeanFromSimOutput','var')
    removeMeanFromSimOutput = false;
end


% -------------------------------------------------------------------------
% Run simulation-output analysis only when both datasets have been supplied
% -------------------------------------------------------------------------

if ~isempty(simWhite_dTheta) && ...
   ~isempty(simAR_dTheta)    && ...
   ~isempty(fsSim)


    simWhite_dTheta = simWhite_dTheta(:);
    simAR_dTheta    = simAR_dTheta(:);


    % Use common duration for direct PSD comparison
    Nsim = min(length(simWhite_dTheta),length(simAR_dTheta));

    whiteOutput = simWhite_dTheta(1:Nsim);
    arOutput    = simAR_dTheta(1:Nsim);


    if removeMeanFromSimOutput

        whiteOutput = whiteOutput - mean(whiteOutput);
        arOutput    = arOutput    - mean(arOutput);

    end


    % ---------------------------------------------------------------------
    % Full sensor-output PSD
    % ---------------------------------------------------------------------

    [PsimWhite,fSimWhite] = pwelch(whiteOutput, ...
                                    welchWindow, ...
                                    welchNoverlap, ...
                                    welchNfft, ...
                                    fsSim);

    [PsimAR,fSimAR] = pwelch(arOutput, ...
                             welchWindow, ...
                             welchNoverlap, ...
                             welchNfft, ...
                             fsSim);


    PsimARcommon = interp1(fSimAR, ...
                           PsimAR, ...
                           fSimWhite, ...
                           'linear', ...
                           'extrap');


    figure('Name','Simulation White vs AR Delta Theta PSD');

    semilogy(fSimWhite,PsimWhite,'LineWidth',1.4);
    hold on;

    semilogy(fSimWhite,PsimARcommon,'LineWidth',1.4);

    grid on;

    xlabel('Frequency [Hz]');
    ylabel(['PSD [(' simSignalUnit ')^2/Hz]']);

    title('Simulated Gyro \Delta\theta Output: White Noise vs AR/Tonal Model');

    legend('RMS White-Noise Model', ...
           'AR / Tonal Noise Model', ...
           'Location','best');

    xlim([0 fsSim/2]);


    results.Simulation.fullOutput.f     = fSimWhite;
    results.Simulation.fullOutput.white = PsimWhite;
    results.Simulation.fullOutput.AR    = PsimARcommon;


    % ---------------------------------------------------------------------
    % Quantify differences at known sensor tone frequencies
    %
    % Here:
    %   Reference  = white-noise simulation
    %   Comparison = AR / tonal simulation
    % ---------------------------------------------------------------------

    if ~isempty(toneFreqHz)

        simToneMetrics = calculateToneMetrics( ...
            fSimWhite, ...
            PsimWhite, ...
            PsimARcommon, ...
            toneFreqHz, ...
            toneSearchHalfWidthHz);


        fprintf('--- SIMULATION OUTPUT TONE COMPARISON ----------------------\n');
        fprintf('Reference  = RMS white-noise simulation\n');
        fprintf('Comparison = AR / tonal simulation\n\n');

        disp(simToneMetrics);

        fprintf('------------------------------------------------------------\n\n');


        results.Simulation.fullOutput.toneMetrics = ...
            simToneMetrics;

    end


    % ---------------------------------------------------------------------
    % OPTIONAL TRUTH-SUBTRACTED DELTA-THETA ERROR PSD
    %
    % This isolates the sensor-error contribution from the deterministic
    % motion of the vehicle.
    % ---------------------------------------------------------------------

    if ~isempty(simWhiteTruth_dTheta) && ...
       ~isempty(simARTruth_dTheta)


        simWhiteTruth_dTheta = simWhiteTruth_dTheta(:);
        simARTruth_dTheta    = simARTruth_dTheta(:);


        Nerror = min([ ...
            length(simWhite_dTheta), ...
            length(simAR_dTheta), ...
            length(simWhiteTruth_dTheta), ...
            length(simARTruth_dTheta)]);


        whiteDeltaThetaError = ...
            simWhite_dTheta(1:Nerror) - ...
            simWhiteTruth_dTheta(1:Nerror);

        arDeltaThetaError = ...
            simAR_dTheta(1:Nerror) - ...
            simARTruth_dTheta(1:Nerror);


        whiteDeltaThetaError = ...
            whiteDeltaThetaError - mean(whiteDeltaThetaError);

        arDeltaThetaError = ...
            arDeltaThetaError - mean(arDeltaThetaError);


        [PwhiteError,fWhiteError] = pwelch( ...
            whiteDeltaThetaError, ...
            welchWindow, ...
            welchNoverlap, ...
            welchNfft, ...
            fsSim);

        [ParError,fARError] = pwelch( ...
            arDeltaThetaError, ...
            welchWindow, ...
            welchNoverlap, ...
            welchNfft, ...
            fsSim);


        ParErrorCommon = interp1( ...
            fARError, ...
            ParError, ...
            fWhiteError, ...
            'linear', ...
            'extrap');


        figure('Name','Simulation Delta Theta Error PSD');

        semilogy(fWhiteError,PwhiteError,'LineWidth',1.4);
        hold on;

        semilogy(fWhiteError,ParErrorCommon,'LineWidth',1.4);

        grid on;

        xlabel('Frequency [Hz]');
        ylabel(['Error PSD [(' simSignalUnit ')^2/Hz]']);

        title(['Gyro \Delta\theta Error PSD: ' ...
               'White Noise vs AR/Tonal Model']);

        legend('RMS White-Noise Model', ...
               'AR / Tonal Noise Model', ...
               'Location','best');

        xlim([0 fsSim/2]);


        results.Simulation.errorOutput.f     = fWhiteError;
        results.Simulation.errorOutput.white = PwhiteError;
        results.Simulation.errorOutput.AR    = ParErrorCommon;


        % -------------------------------------------------------------
        % Tone comparison on isolated measurement error
        % -------------------------------------------------------------

        if ~isempty(toneFreqHz)

            simErrorToneMetrics = calculateToneMetrics( ...
                fWhiteError, ...
                PwhiteError, ...
                ParErrorCommon, ...
                toneFreqHz, ...
                toneSearchHalfWidthHz);


            fprintf('--- DELTA-THETA ERROR TONE COMPARISON ----------------------\n');
            fprintf('Reference  = white-noise delta-theta error\n');
            fprintf('Comparison = AR / tonal delta-theta error\n\n');

            disp(simErrorToneMetrics);

            fprintf('------------------------------------------------------------\n\n');


            results.Simulation.errorOutput.toneMetrics = ...
                simErrorToneMetrics;

        end


    else

        fprintf(['Simulation truth data not supplied.\n' ...
                 'Full delta-theta PSD comparison was generated, but\n' ...
                 'truth-subtracted delta-theta error PSD was skipped.\n\n']);

    end


else

    fprintf(['Simulation comparison section skipped.\n' ...
             'Populate simWhite_dTheta, simAR_dTheta, and fsSim when\n' ...
             'the two simulation datasets are available.\n\n']);

end


%% ========================================================================
%  10. FINAL SUMMARY
%
%  WHAT THIS PROVIDES
%  ------------------
%  At this point the validation package contains:
%
%  1. PSD agreement
%  2. PSD RMSE in dB
%  3. RMS agreement
%  4. Quantitative tone-frequency / tone-power errors
%  5. Autocorrelation agreement
%  6. L2-based deviation metrics
%  7. Allan-deviation agreement
%  8. AR innovation whiteness
%  9. Optional white-noise vs AR-model simulated delta-theta PSD
%
%  Together these separate:
%
%       MODEL VALIDATION
%
%  from
%
%       SIMULATION IMPACT
%
% =========================================================================


fprintf('\n============================================================\n');
fprintf('VALIDATION COMPLETE\n');
fprintf('============================================================\n');

fprintf('PSD RMSE               : %.6f dB\n',psdRMSE_dB);
fprintf('PSD relative L2        : %.6f\n',psdRelativeL2);
fprintf('ACF relative L2        : %.6f\n',acfRelativeL2);
fprintf('Test RMS               : %.10g %s\n',testRMS_time,signalUnit);
fprintf('AR RMS                 : %.10g %s\n',arRMS_time,signalUnit);
fprintf('RMS error              : %.4f %%\n',rmsErrorPercent);
fprintf('Innovation flatness    : %.6f\n',innovationSpectralFlatness);
fprintf('Innovation ACF RMS     : %.6f\n',innovationACFrms);

if doAllanDeviation && exist('allanRMSE_dB','var')
    fprintf('Allan RMSE             : %.6f dB\n',allanRMSE_dB);
end

fprintf('============================================================\n\n');


%% ========================================================================
%  11. OPTIONAL SAVE
% =========================================================================


if saveResults

    save(resultsFileName,'results');

    fprintf('Results saved to:\n%s\n\n',resultsFileName);

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% LOCAL FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


function toneTable = calculateToneMetrics( ...
    f, ...
    PReference, ...
    PComparison, ...
    expectedToneFreqHz, ...
    searchHalfWidthHz)

% CALCULATETONEMETRICS
%
% For each expected tone:
%
% 1. Search for the largest PSD peak in a local band.
% 2. Determine the frequency error.
% 3. Determine peak PSD error in dB.
% 4. Integrate PSD over the local band.
% 5. Calculate local bandpower percent error.


    expectedToneFreqHz = expectedToneFreqHz(:);

    nTones = length(expectedToneFreqHz);


    referencePeakFreq = nan(nTones,1);
    comparisonPeakFreq = nan(nTones,1);

    frequencyError = nan(nTones,1);

    referencePeakPSD_dB = nan(nTones,1);
    comparisonPeakPSD_dB = nan(nTones,1);

    peakError_dB = nan(nTones,1);

    referenceBandPower = nan(nTones,1);
    comparisonBandPower = nan(nTones,1);

    bandPowerErrorPercent = nan(nTones,1);


    for i = 1:nTones

        f0 = expectedToneFreqHz(i);


        searchMask = ...
            f >= max(0,f0-searchHalfWidthHz) & ...
            f <= f0+searchHalfWidthHz;


        if nnz(searchMask) < 1
            continue;
        end


        fLocal = f(searchMask);

        PrefLocal = PReference(searchMask);
        PcompLocal = PComparison(searchMask);


        % Peak location
        [referencePeakPower,indexReference] = max(PrefLocal);

        [comparisonPeakPower,indexComparison] = max(PcompLocal);


        referencePeakFreq(i) = ...
            fLocal(indexReference);

        comparisonPeakFreq(i) = ...
            fLocal(indexComparison);


        frequencyError(i) = ...
            comparisonPeakFreq(i) - ...
            referencePeakFreq(i);


        % Peak PSD error
        referencePeakPSD_dB(i) = ...
            10*log10(max(referencePeakPower,realmin));

        comparisonPeakPSD_dB(i) = ...
            10*log10(max(comparisonPeakPower,realmin));


        peakError_dB(i) = ...
            comparisonPeakPSD_dB(i) - ...
            referencePeakPSD_dB(i);


        % Integrated local bandpower
        if length(fLocal) > 1

            referenceBandPower(i) = ...
                trapz(fLocal,PrefLocal);

            comparisonBandPower(i) = ...
                trapz(fLocal,PcompLocal);

        else

            referenceBandPower(i) = ...
                referencePeakPower;

            comparisonBandPower(i) = ...
                comparisonPeakPower;

        end


        bandPowerErrorPercent(i) = ...
            100 * ...
            (comparisonBandPower(i)-referenceBandPower(i)) / ...
            max(referenceBandPower(i),eps);

    end


    toneTable = table( ...
        (1:nTones)', ...
        expectedToneFreqHz, ...
        referencePeakFreq, ...
        comparisonPeakFreq, ...
        frequencyError, ...
        referencePeakPSD_dB, ...
        comparisonPeakPSD_dB, ...
        peakError_dB, ...
        referenceBandPower, ...
        comparisonBandPower, ...
        bandPowerErrorPercent, ...
        'VariableNames',{ ...
        'Tone', ...
        'ExpectedFreq_Hz', ...
        'ReferencePeakFreq_Hz', ...
        'ComparisonPeakFreq_Hz', ...
        'FreqError_Hz', ...
        'ReferencePeakPSD_dB', ...
        'ComparisonPeakPSD_dB', ...
        'PeakError_dB', ...
        'ReferenceBandPower', ...
        'ComparisonBandPower', ...
        'BandPowerError_pct'});

end


function [tau,adev] = overlappingAllanDeviation(x,fs,mValues)

% OVERLAPPINGALLANDEVIATION
%
% Computes overlapping Allan deviation for a uniformly sampled sequence.
%
% x       : sampled gyro-rate residual
% fs      : sample rate [Hz]
% mValues : averaging cluster sizes in samples
%
% tau = m/fs
%
% For each cluster size m:
%
%   1. Calculate every overlapping m-point average.
%   2. Compare averages separated by m samples.
%   3. Allan variance = 0.5 * mean(deltaAverage^2)


    x = x(:);

    N = length(x);

    mValues = unique(mValues(:));


    tau  = nan(size(mValues));
    adev = nan(size(mValues));


    cumulativeX = [0; cumsum(x)];


    for i = 1:length(mValues)

        m = mValues(i);


        if 2*m >= N
            continue;
        end


        % Every overlapping m-sample average
        clusterAverage = ...
            (cumulativeX(1+m:end) - ...
             cumulativeX(1:end-m)) / m;


        % Difference between averages separated by one averaging interval
        deltaAverage = ...
            clusterAverage(1+m:end) - ...
            clusterAverage(1:end-m);


        allanVariance = ...
            0.5 * mean(deltaAverage.^2);


        tau(i) = m/fs;

        adev(i) = sqrt(allanVariance);

    end


    valid = isfinite(tau) & isfinite(adev);

    tau  = tau(valid);
    adev = adev(valid);

end


function SF = spectralFlatness(P)

% SPECTRALFLATNESS
%
% Spectral flatness:
%
%           geometric mean of PSD
%   SF = ---------------------------
%          arithmetic mean of PSD
%
% SF approaches 1 for a flat spectrum.
% SF decreases as spectral concentration / coloring increases.


    P = P(:);

    P = max(P,realmin);


    SF = exp(mean(log(P))) / mean(P);

end
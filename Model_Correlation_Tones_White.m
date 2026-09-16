%% TONE-ONLY / TONE + WHITE-NOISE VALIDATION
% Requires: toneModel, x_ds, ts_ds, te_ds, Fs

clc; close all; rng(1);

regimeToUse = 2;
nRealizations = 100;
model = toneModel(regimeToUse);

%% TEST + FITTED TONES
xTest = x_ds(ts_ds(regimeToUse):te_ds(regimeToUse));
xTest = xTest(:);
N = length(xTest);
t = (0:N-1)'/Fs;

tones = zeros(N,1);
for j = 1:length(model.toneFreq)
    tones = tones + model.toneAmp(j)*sin( ...
        2*pi*model.toneFreq(j)*t + model.tonePhase(j));
end

biasTest = model.bias;
residual = xTest - biasTest - tones;
whiteSigma = sqrt(mean(residual.^2));

% Candidate 1: deterministic tones only
modelTone = biasTest + tones;

% Candidate 2: same tones + white noise with the test residual RMS
whiteNoise = whiteSigma*randn(N,nRealizations);
modelWhite = biasTest + tones + whiteNoise;

%% PSDs
% Demean so the stationary bias does not dominate the DC bin.
[Ptest,f] = pwelch(xTest-mean(xTest),[],[],[],Fs);
[Ptone,~] = pwelch(modelTone-mean(modelTone),[],[],[],Fs);
[PwhiteEach,~] = pwelch(modelWhite-mean(modelWhite,1),[],[],[],Fs);
Pwhite = mean(PwhiteEach,2);

[Presidual,~] = pwelch(residual-mean(residual),[],[],[],Fs);
[PwhiteResidualEach,~] = pwelch(whiteNoise-mean(whiteNoise,1),[],[],[],Fs);
PwhiteResidual = mean(PwhiteResidualEach,2);

%% PLOTS
cTest  = [0.0000 0.4470 0.7410];
cWhite = [0.4660 0.6740 0.1880];
cTone  = [0.4940 0.1840 0.5560];

figure('Name','Tone + White-Noise Validation');
tiledlayout(2,1);

nexttile;
semilogy(f,Ptest,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,Ptone,'Color',cTone,'LineWidth',2);
semilogy(f,Pwhite,'Color',cWhite,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Full Test vs Simplified Models');
legend('Test','Tones Only','Tones + Mean White Noise','Location','best');

nexttile;
semilogy(f,Presidual,'Color',cTest,'LineWidth',2); hold on;
semilogy(f,PwhiteResidual,'Color',cWhite,'LineWidth',2);
grid on; xlim([0 Fs/2]);
xlabel('Frequency [Hz]'); ylabel('PSD [units^2/Hz]');
title('Test Residual vs White-Noise Approximation');
legend('Test Residual','Mean White Noise','Location','best');

%% VALUES TO COPY INTO C++
fprintf('\nREGIME %d\n',regimeToUse)
fprintf('Bias = %.12g\n',biasTest)
fprintf('White noise sigma = %.12g\n',whiteSigma)
fprintf('Tone frequency = ['); fprintf(' %.12g',model.toneFreq); fprintf(' ]\n')
fprintf('Tone amplitude = ['); fprintf(' %.12g',model.toneAmp); fprintf(' ]\n')
fprintf('Tone phase = ['); fprintf(' %.12g',model.tonePhase); fprintf(' ]\n')

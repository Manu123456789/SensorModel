%% AR + TONE HISTOGRAM CHECK
% Run after loading sensorModel.
% Required fields: Fs, residual, toneFreq, toneAmp, tonePhase, noiseA, noiseB
% Sections 1-3 reproduce the generation and histogram method in V4_new.
% Section 4 adds histogram variability checks.
% No averaging of model time histories and no per-run RMS rescaling.

%% 1. SETTINGS AND TEST SIGNAL
rng(1);
regimeToUse = 2;
nRealizations = 500;
ampBins = 60;

model = sensorModel(regimeToUse);
Fs = model.Fs;
residual = model.residual(:);
residual = residual - mean(residual);
N = length(residual);
t = (0:N-1)'/Fs;

% Use the SAME time origin, sine/cosine convention, and phases used
% when subtracting tones to create model.residual.
toneModel = zeros(N,1);
for j = 1:length(model.toneFreq)
    toneModel = toneModel + model.toneAmp(j)*sin( ...
        2*pi*model.toneFreq(j)*t + model.tonePhase(j));
end
toneModel = toneModel - mean(toneModel);

% Reconstructed bias-removed test signal.
% This equals the original centered test only if tone reconstruction matches.
testFull = residual + toneModel;
testFull = testFull - mean(testFull);

%% 2. GENERATE INDEPENDENT AR + TONE RECORDS
% noiseB is the numerator/amplitude gain, NOT innovation variance.
% For scalar-gain AR from [A,E] = arburg(...), use noiseA=A, noiseB=sqrt(E).
% If noiseB already stores the correct gain, do not take another square root.
burnIn = max(10*(max(length(model.noiseA),length(model.noiseB))-1), ...
    round(5*Fs));

w = randn(N+burnIn,nRealizations);        % One independent input per column
arTemp = filter(model.noiseB,model.noiseA,w);
arNoise = arTemp(burnIn+1:end,:);        % N samples per realization
arNoise = arNoise - mean(arNoise,1);    % Remove each column's sample mean

modelFull = toneModel + arNoise;        % Same tones added to every column
modelFull = modelFull - mean(modelFull,1);

%% 3. ORIGINAL FULL-SIGNAL HISTOGRAM
% Shared edges, physical amplitude units, PDF normalization.
ampLimit = max([max(abs(testFull)),max(abs(modelFull(:)))]);
if ampLimit == 0
    ampLimit = 1;
end
ampEdges = linspace(-ampLimit,ampLimit,ampBins+1);

figure('Name','Full-Signal Amplitude Distributions');
histogram(testFull,ampEdges,'Normalization','pdf', ...
    'DisplayStyle','stairs','EdgeColor',[0 0.4470 0.7410],'LineWidth',2);
hold on;
histogram(modelFull(:),ampEdges,'Normalization','pdf', ...
    'DisplayStyle','stairs','EdgeColor',[0.4660 0.6740 0.1880], ...
    'LineWidth',2);
grid on; xlim([-ampLimit ampLimit]);
xlabel('Bias-Removed Sensor Error'); ylabel('Probability Density');
title('Full-Signal Amplitude Distribution');
legend('Test',sprintf('AR + Tones (%d runs pooled)',nRealizations), ...
    'Location','best');

%% 4. NEW DIAGNOSTIC: INDIVIDUAL HISTOGRAMS AND THEIR SPREAD
% Each hEach column is the PDF histogram of ONE equal-length record.
% The band spans the 2.5th-97.5th percentiles across runs AT EACH BIN.
% It is a pointwise model simulation range, not a confidence band on the
% mean, a simultaneous 95% acceptance region, or a formal goodness-of-fit test.
% Diagnostic curves connect bin centers; section 3 shows original stairs.
figure('Name','Histogram Variability: Full Signal and Residual');
tiledlayout(2,1);

for q = 1:2
    if q == 1
        testData = testFull;
        simData = modelFull;
        label = 'Full signal: test vs AR + tones';
    else
        testData = residual;
        simData = arNoise;
        label = 'Residual: test vs AR only';
    end

    L = max([max(abs(testData)),max(abs(simData(:)))]);
    if L == 0
        L = 1;
    end
    edges = linspace(-L,L,ampBins+1);
    centers = (edges(1:end-1) + edges(2:end))/2;

    hTest = histcounts(testData,edges,'Normalization','pdf').';
    hEach = zeros(ampBins,nRealizations);
    for k = 1:nRealizations
        hEach(:,k) = histcounts(simData(:,k),edges, ...
            'Normalization','pdf').';
    end
    hMean = mean(hEach,2);
    hBand = prctile(hEach,[2.5 97.5],2);

    % Exact equivalence, up to floating-point roundoff, for equal lengths.
    hPool = histcounts(simData(:),edges,'Normalization','pdf').';
    fprintf('%s: max |pooled PDF - mean PDF| = %.3g\n', ...
        label,max(abs(hPool-hMean)));

    nexttile;
    hRange = fill([centers fliplr(centers)], ...
        [hBand(:,1).' fliplr(hBand(:,2).')], ...
        [0.85 0.91 1],'EdgeColor','none');
    hold on;
    plot(centers,hEach(:,1:min(3,nRealizations)), ...
        'Color',[0.65 0.65 0.65],'HandleVisibility','off');
    hModel = plot(centers,hMean,'r-','LineWidth',1.8);
    hMeasured = plot(centers,hTest,'k-','LineWidth',2);
    grid on; xlim([-L L]);
    xlabel('Bias-Removed Sensor Error'); ylabel('Probability Density');
    title([label ' (gray = first 3 runs)']);
    legend([hMeasured hModel hRange], ...
        {'Test','Model mean PDF','95% pointwise run range'}, ...
        'Location','best');
end


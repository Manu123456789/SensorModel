# Sensor Error Model: Slide Guide

This is an eight-slide content guide. Each slide separates audience-facing text from figure placement and speaker notes. Replace each **INSERT** placeholder with your own values or results. The notes provide additional explanation for questions and do not all belong on the slides.

## Presentation structure

| Slide | Section | Slide title | Main visual or equation |
| --- | --- | --- | --- |
| 1 | Summary | Test-derived sensor error model | Short summary and one result placeholder |
| 2 | Data processing | Test data and dominant tone frequencies | FFT with selected tones marked |
| 3 | Data processing | Tone fitting and stochastic residual | Sine/cosine fit, amplitude/phase conversion, residual |
| 4 | Model identification | AR identification with Yule–Walker | AR model, Yule–Walker relation, shaping filter |
| 5 | Simulation implementation | Sensor error generation in the simulation | Seven numbered update steps |
| 6 | Simulation implementation | AR recursion and tone synthesis | Runtime recurrence and time-dependent tones |
| 7 | Validation | Power spectral density and broadband RMS | PSD overlay and a small RMS table |
| 8 | Validation | Autocorrelation and noise memory | Normalized autocorrelation overlay |

For a brief audience, present slide 1 and continue to the validation figures or your later vehicle results. For a technical audience, follow slides 2–8. Keep simulation implementation to slides 5 and 6: show the update sequence once, then explain the two calculations that drive it. There is no separate order-selection slide or frame-transformation slide.

**Estimator version note:** Slide 4 describes your original Yule–Walker workflow, as requested. The MATLAB file updated in this conversation now uses `arburg`. Label the method according to the coefficients used for the results you present. A short replacement description for Burg appears in slide 4's notes. The simulation equations apply to either estimator.

**Notation:** $k$ is the sample index, $F_s$ is the model sample rate, $N_t$ is the number of explicit tones, and $p$ is the AR order. The measured residual is $r[k]$. The generated stochastic noise is $n[k]$. Their individual samples need not coincide.

---

## Slide 1: Test-derived sensor error model

### On-slide content

**Objective:** Represent measured sensor-error characteristics in the simulation.

- Separate each test regime into stationary bias, explicit tones, and stochastic residual noise.
- Represent the residual with an AR shaping filter driven by Gaussian white noise.
- Reconstruct the error during sensor updates using the filter and fitted tones.
- Check the generated noise against test data using PSD, broadband RMS, and autocorrelation.

**Result:** INSERT one sentence describing the agreement demonstrated by your plots.

### Placement

Use the objective as the opening sentence, followed by the four short bullets. Reserve the bottom of the slide for the result sentence. Detailed equations begin on slide 3.

### Speaker notes

Suggested opening:

> I used sensor test data to build an error generator for the simulation. I separated the mean offset and repeatable tones, then fitted a stochastic model to the remaining colored noise. The simulation generates new noise with that structure, and I check its spectrum, overall noise level, and correlation over time against the measurements.

Insert a measured conclusion only after selecting the figures you will present. Agreement at the sensor-noise level is the conclusion for this section. The effect on vehicle behavior belongs in your later results section.

---

## Slide 2: Test data and dominant tone frequencies

### On-slide content

1. Select the test samples for the operating regime.
2. Downsample to the model sample rate.
3. Subtract the regime mean with an expected baseline of zero.
4. Use the FFT to select dominant tone frequencies.

**Record:** INSERT regime name, sensor quantity and units, acquisition rate, model rate, and record duration.

**Processing note:** No anti-alias filter was applied.

### Figure placement

**Primary figure:** Place the FFT of the de-biased, downsampled signal on the right, occupying roughly two-thirds of the slide. Mark the selected frequencies $f_1,\ldots,f_{N_t}$. Label frequency in Hz and amplitude in the sensor's units.

**Optional supporting figure:** Add a small PSD below the FFT only if it helps distinguish the peaks from the surrounding noise. Give the FFT priority when space is limited. A small time-history inset can identify the selected regime if the audience needs that context.

### Speaker notes

- Each regime has its own fitted parameters. The stationary-noise approximation applies within that selected regime.
- Removing the mean isolates fluctuations. Store that mean as the stationary bias because the expected baseline is zero. No bias-removal equation is needed on this slide.
- The FFT identifies candidate frequencies. The next step estimates amplitudes and phases jointly at those frequencies.
- The supplied MATLAB code selects FFT-bin frequencies. It does not refine the frequencies between bins or independently demonstrate that a peak persists over time.
- Omitting anti-alias filtering means higher-frequency content may fold into the retained band. Describe the resulting model as a model of the processed samples used for identification.
- Use the actual sampling values in the record label. In the supplied example, rounding indices for 1,000 Hz to 80 Hz alternates between 12- and 13-sample gaps. If that example is still in use, the retained timestamps are only approximately a uniform 80 Hz grid. The later equations assume a uniform model grid.

---

## Slide 3: Tone fitting and stochastic residual

### On-slide content

**Fit the sine and cosine coefficients jointly by least squares at the selected frequencies.**

$$
x_{\mathrm{tone}}[k]
=\sum_{j=1}^{N_t}
\left[c_j\sin(2\pi f_j t_k)+d_j\cos(2\pi f_j t_k)\right],
\qquad t_k=\frac{k}{F_s}.
$$

**Convert each coefficient pair to amplitude and phase.**

$$
A_j=\sqrt{c_j^2+d_j^2},
\qquad
\phi_j=\mathrm{atan2}(d_j,c_j).
$$

**Reconstruct the fitted tones and subtract them to obtain the residual.**

$$
\begin{aligned}
x_{\mathrm{tone}}[k]
&=\sum_{j=1}^{N_t}A_j\sin(2\pi f_j t_k+\phi_j),\\
r[k]&=x_{\mathrm{DS}}[k]-\mu_b-x_{\mathrm{tone}}[k].
\end{aligned}
$$

Here $x_{\mathrm{DS}}$ is the downsampled measurement and $\mu_b$ is its regime mean.

### Placement

Use the fitted sine/cosine expression across the top. Place the amplitude and phase conversion in the middle. Put the final tone representation and residual equation together at the bottom. These equations are the main visual. A residual plot is unnecessary.

### Speaker notes

The fit is linear in $c_j$ and $d_j$ once the frequencies are fixed. Form a design matrix $\Phi$ whose paired columns contain the sine and cosine basis functions. If $\mathbf{x}_0$ is the de-biased data vector, solve

$$
\widehat{\boldsymbol{\beta}}
=\mathrm{arg\,min}_{\boldsymbol{\beta}}
\left\|\mathbf{x}_0-\Phi\boldsymbol{\beta}\right\|_2^2,
\qquad
\boldsymbol{\beta}=[c_1,d_1,\ldots,c_{N_t},d_{N_t}]^{\mathsf T}.
$$

This is the operation implemented by `beta = H\x0` in MATLAB. The notation $\Phi$ here distinguishes the fitting matrix from the shaping filter $H(z)$ on the next slide.

The conversion follows from expanding the phase-shifted sine: $c_j=A_j\cos\phi_j$ and $d_j=A_j\sin\phi_j$. Use `atan2` to retain the correct phase quadrant. $A_j$ is peak amplitude, and $\phi_j$ is in radians relative to the fitted record's time origin.

The residual is the part assigned to the stochastic model. It can remain colored and can still contain broad peaks or imperfectly removed tonal content. It does not need a flat PSD. At this point, the data-processing stage is complete.

---

## Slide 4: AR identification with Yule–Walker

### On-slide content

**Represent the residual as an autoregressive process.**

$$
r[k]+\sum_{i=1}^{p}a_i r[k-i]=\varepsilon[k].
$$

**Estimate the coefficients from the residual autocorrelation.**

$$
\widehat R_r[\ell]
+\sum_{i=1}^{p}a_i\widehat R_r[\ell-i]=0,
\qquad \ell=1,\ldots,p.
$$

**The identified model becomes an all-pole shaping filter.**

$$
H(z)=\frac{b_{\mathrm{noise}}}{1+\sum_{i=1}^{p}a_i z^{-i}},
\qquad b_{\mathrm{noise}}=\sqrt{\sigma_\varepsilon^2}.
$$

**Stored per regime:** Sample rate, stationary bias, tone frequencies, amplitudes and phases, AR denominator coefficients, and innovation gain.

### Placement

Arrange the three equation groups vertically with one short explanation for each. Use the stored-parameter list as a final line. Keep the matrix derivation and estimator details in the speaker notes.

### Speaker notes

The Yule–Walker relation follows by multiplying the AR equation by an earlier residual sample and taking an expectation. The innovation is uncorrelated with those past samples. Replacing the unknown correlations with estimates gives a linear system for the AR coefficients.

For real data, a compact matrix form is

$$
T\mathbf a=-\mathbf g,
\qquad
T_{ij}=\widehat R_r[|i-j|],
\qquad
g_i=\widehat R_r[i],
\qquad i,j=1,\ldots,p.
$$

Here $\mathbf a=[a_1,\ldots,a_p]^{\mathsf T}$ excludes the leading coefficient $a_0=1$. The minus sign agrees with MATLAB's denominator-coefficient convention. Durbin gives the corresponding equations in Section 2, equation (6), on printed page 3 of the supplied paper.

MATLAB `aryule` uses the biased sample-autocorrelation estimate and solves the system with the Levinson–Durbin recursion. It returns the normalized denominator and the estimated innovation variance. [MathWorks: aryule](https://www.mathworks.com/help/signal/ref/aryule.html)

For this Yule–Walker fit, the variance estimate satisfies

$$
\widehat\sigma_\varepsilon^2
=\widehat R_r[0]+\sum_{i=1}^{p}a_i\widehat R_r[i].
$$

Taking its square root gives the gain for a unit-variance white-noise input. The innovation variance is different from the output residual variance: the denominator also changes output power. The $p+1$ denominator coefficients include $a_0$. There is one numerator gain.

**Stored model and CSV handoff:** The MATLAB `sensorModel` structure retains the sample rate and bias as well as the tone and filter parameters. The current seven-column CSV exports the filter order, tone count, tone parameters, denominator coefficients, and scalar gain. It does not export sample rate or bias. Those settings come from the simulation configuration and existing bias path.

**If presenting the current Burg-generated results:** Use the title "AR identification with Burg." Keep the AR-process equation, shaping filter, and stored-parameter line. Replace the Yule–Walker estimation equation with this sentence: "Estimate the AR coefficients by minimizing forward and backward prediction errors through Burg's recursion." Obtain the gain from the variance returned by `arburg`. This describes the recent estimator change without changing the simulation architecture. [MathWorks: Burg method](https://www.mathworks.com/help/signal/ug/parametric-methods.html)

---

## Slide 5: Sensor error generation in the simulation

### On-slide content

**Before updates:** Load the selected regime CSV once and allocate persistent memory for $p$ stochastic outputs.

1. Generate a unit-Gaussian innovation.
2. Compute the AR colored-noise output.
3. Update the stochastic output history.
4. Evaluate the explicit tones using simulation time.
5. Combine the colored noise and tones in the sensor frame.
6. Rotate the combined noise into the platform frame.
7. Inject it through the existing sensor path, with bias applied once.

### Placement

Show the seven steps as short numbered rows. Give steps 2 and 4 slightly stronger emphasis because slide 6 explains their equations. Use the setup statement above the list. No separate rotation diagram is needed.

### Speaker notes

Introduce the full sequence once. On the next slide, refer back to steps 2 and 4 rather than repeating the list.

The CSV loader determines the order and tone count from the file. It loads all denominator coefficients and one gain, plus the frequency, amplitude, and phase of each tone. The coefficient arrays remain fixed for the selected model, while the history changes at every sensor update.

The current C++ code combines stochastic noise and tones before rotation. It applies bias separately through `bias(i)` in the final measurement calculation. That is why the seven-step list places the existing bias path in step 7. Do not describe the bias as a value that this CSV loader supplies.

The AR update must run at the model's sample rate, once per intended sensor sample. Match the quantity and units represented by the test data to the simulation injection point.

The supplied function uses mutable static history, which persists between calls. Each independent sensor realization needs its own state and appropriate initialization. The supplied file begins that history at zero. Mention a warm-up interval only if you actually used one in the runs being presented.

---

## Slide 6: AR recursion and tone synthesis

### On-slide content

**Step 2: Compute the stochastic output using the stored history.**

$$
n[k]=\frac{b_{\mathrm{noise}}w[k]-\sum_{i=1}^{p}a_i n[k-i]}{a_0},
\qquad w[k]\sim\mathcal N(0,1).
$$

After computing $n[k]$, shift the history and store it as the newest stochastic output.

**Step 4: Recompute the instantaneous tones at each update.**

$$
x_{\mathrm{tone}}(t_k)
=\sum_{j=1}^{N_t}A_j\sin(2\pi f_jt_k+\phi_j).
$$

Use simulation time $t_k$ in seconds. Add the tones after the stochastic recursion. The history contains only $n[k]$.

### Placement

Give the AR recurrence the upper half of the slide, with the history-update sentence directly below it. Put the time-dependent tone equation in the lower half. The repeated tone equation now explains runtime evaluation, so the amplitude/phase derivation from slide 3 does not need to appear again.

### Speaker notes

In the C++ code, `random_noise[1]` supplies the innovation for the modeled sensor axis. The required input is independent, zero-mean Gaussian noise with unit variance. `noise_model_b` scales it. The loop subtracts each coefficient times its stored stochastic output and then divides by `noise_model_a[0]`. This directly implements the displayed recurrence.

For both `aryule` and `arburg`, the leading coefficient is one. Keeping the division implements the general form. Shift the history from the highest index toward the lowest, then put the new output into index zero.

`sensor_time = global_time` supplies the time argument for the tone calculation. The factor $2\pi f_jt_k$ advances phase as time progresses. The stored amplitudes, frequencies, and phase offsets stay constant within the selected regime.

The fitted phases refer to a record that starts at local time zero. The C++ implementation uses global simulation time. Those origins must be consistent if you want a particular phase alignment with a test segment or a regime start. Changing the time origin shifts phase.

**Injection detail for questions:** In the supplied C++ file, the existing downstream calculation uses `delta_noise[i] = noise[i] - internal_data.noise[i]`. It then adds `delta_noise[i]`, `bias(i)`, and the other existing error terms to the measurement. The downstream delta therefore includes additional processing beyond the raw AR-plus-tone generator. Use the raw generated noise for its direct PSD comparison with the corresponding test signal. Discuss the final measurement and vehicle response in the later results section.

---

## Slide 7: Power spectral density and broadband RMS

### On-slide content

- PSD agreement checks the spectral shape, noise-floor level, and dominant tone content.
- Broadband RMS agreement checks the total fluctuating power over the modeled bandwidth.

$$
\widehat{\mathrm{RMS}}_{\mathrm{noise}}
=\sqrt{\int_0^{F_s/2}\widehat S_{xx}(f)\,df}.
$$

| Quantity | Test | Generated model |
| --- | --- | --- |
| Broadband RMS, INSERT units | INSERT value | INSERT value |

**Finding:** INSERT one sentence supported by the PSD overlay and RMS values.

### Figure placement

**Primary figure:** A large PSD overlay of the de-biased test signal and the generated AR-plus-tone signal for one labeled regime. Use clear test/model colors. Label frequency in Hz and PSD in squared sensor units per Hz, or the corresponding dB scale.

Place the small RMS table below the plot or in a narrow side column. State the integration band in the caption. Keep a residual-only comparison as supporting material if you already have it, rather than adding another required slide.

### Speaker notes

The graph shows how power is distributed across frequency. The RMS value summarizes its integral. The same RMS can arise from different spectral shapes, so show both.

Use the same Welch window, segment length, overlap, and frequency normalization for the overlay. A generated random sequence should reproduce the relevant statistics without matching the measured samples point by point.

The proposed main figure includes tones and excludes stationary bias on both curves. Its RMS therefore includes tonal power. The stored MATLAB `sensorModel.noiseRMS` is computed from the residual after tone removal. Use that stored value only for a residual-versus-AR comparison, or compute both full-signal RMS values for the main figure described here.

Use the generated signal before downstream differencing or other sensor processing when comparing directly against that same quantity in the test record. This keeps the claim on this slide tied to the generator being validated.

If using multiple model realizations, a mean curve with a light gray band can show model variability. Label what the band represents. A band of generated realizations does not quantify all uncertainty in the measured record.

The PSD integral uses the one-sided PSD in linear power units. Convert dB values back to linear units before integration if necessary. MATLAB's `pwelch` output is already linear power density. [MathWorks: pwelch](https://www.mathworks.com/help/signal/ref/pwelch.html)

---

## Slide 8: Autocorrelation and noise memory

### On-slide content

**Question:** How are noise samples related when they are separated in time?

- A shaping filter gives noise memory: a random input can influence several later outputs.
- Compare the test residual with the model autocorrelation averaged over 500 runs, then normalized.
- Agreement away from zero supports the model's ability to reproduce the measured noise memory.

$$
\rho_x[\ell]=\frac{R_x[\ell]}{R_x[0]},
\qquad \tau=\frac{\ell}{F_s}.
$$

**Finding:** INSERT the lag range with supported agreement and describe any remaining difference near the extremes. Pair this conclusion with the residual PSD and RMS results.

### Figure placement

Use the residual autocorrelation panel from `Model_Correlation_v3.txt`. Plot time lag in seconds on the horizontal axis and normalized autocorrelation on the vertical axis, with limits of approximately -2 to +2 seconds when the record supports that range.

Use the legend labels **Test residual** and **AR model: 500-run average ACF, normalized**. Caption: "Bias and fitted tones removed from the test; stochastic AR output only on the model side. Equal record lengths and sample rates."

Place the question and brief bullets beside the figure. Keep the explanations below in speaker notes. If the agreement is strongest within about 1.5 seconds, distinguish that observation from the full displayed range; do not describe the entire range as matched just because it is plotted.

### Speaker notes: start from individual noise samples

The generator produces a different random sequence on each run. The property we want to preserve is how errors at different times relate to one another. Do they tend to reinforce one another, oppose one another, or have little relationship at a particular separation?

To estimate autocorrelation, take one mean-removed record and make a shifted copy. Pair the overlapping samples, multiply each pair, and combine those products. Repeat for different shifts. Each record is compared with itself; we then compare the resulting test and model curves. This does not require the generated waveform to track the measured waveform.

For a zero-mean stationary process, the underlying quantity is

$$
R_x[\ell]=\mathrm{E}\{x[k]x[k-\ell]\}.
$$

Here, the expectation means an average over the random process. A finite record supplies an estimate. In the sample products, two deviations on the same side of the mean contribute positively; deviations on opposite sides contribute negatively. [MathWorks: correlation and covariance](https://www.mathworks.com/help/signal/ug/correlation-and-covariance.html)

| Autocorrelation at a chosen lag | Intuitive interpretation |
| --- | --- |
| Positive | Same-direction deviations dominate the average product: errors tend to reinforce one another at this separation. |
| Negative | Opposite-direction deviations dominate: errors tend to counteract one another at this separation. |
| Near zero | Little linear relationship remains at this separation. This alone does not establish independence. |

A lag of 1.5 seconds compares samples separated by 1.5 seconds throughout the record. It is not time since the simulation started. For real-valued autocorrelation, the negative-lag side mirrors the positive-lag side and supplies the same information.

Both curves can remain negative outside the central peak and still agree well. If a negative curve rises and falls, the opposing relationship becomes weaker and stronger; it need not cross zero. Negative autocorrelation does not mean the noise itself remains negative or reverses sign on a fixed schedule.

At zero lag, every sample is multiplied by itself, so the unnormalized value represents mean-square noise level. Normalization divides out that level and makes both curves equal one at zero. That agreement is automatic; agreement at nonzero lags is informative. RMS supplies the noise magnitude removed by normalization. [MathWorks: xcorr](https://www.mathworks.com/help/matlab/ref/xcorr.html)

### Speaker notes: how a filter creates noise memory

Independent, zero-mean white Gaussian inputs have zero theoretical autocorrelation at every nonzero lag. In a shaping filter, an input can contribute to several outputs. Those outputs then share some of the same random input, creating correlation. Your AR recurrence does this through its stored previous outputs. The coefficients determine the strength, sign, and duration of that relationship.

**Simple illustration, not the fitted sensor model:** Compare unit-RMS white noise $w[k]$ with

$$
v[k]=\frac{w[k]+w[k-1]}{\sqrt{2}}.
$$

Both have RMS one. Adjacent white-noise samples are uncorrelated. Adjacent samples of $v[k]$ share one input, so their theoretical normalized autocorrelation is 0.5. At separations of two or more samples, they share no inputs and the correlation is zero. This example shows why matching RMS alone cannot establish that a generator has the correct time behavior.

An AR filter can retain influence for many updates because its history is fed back recursively. The AR order is not a hard cutoff on the longest possible correlation lag.

### Speaker notes: what the 500-run comparison actually does

The supplied script compares the measured residual with generated stochastic AR noise. Bias and fitted tones have already been removed from the residual; the explicit tones are also absent from this model comparison. This directly checks the noise-shaping filter.

| Stage | What the supplied script does |
| --- | --- |
| Test curve | Removes the residual mean and calls `xcorr(residual,maxLag,'coeff')`. |
| Model runs | Uses the same filter coefficients with 500 independent Gaussian input sequences, discards an initial burn-in interval, and retains the test record's length for each run. Each retained run is mean-removed. |
| Model curve | Computes `xcorr(...,'biased')` separately for each run, averages those curves, and divides by the averaged zero-lag value. |

Using $q$ to index the runs, the final model curve is

$$
\overline R[\ell]=\frac{1}{500}\sum_{q=1}^{500}\widehat R_q[\ell],
\qquad
\widehat\rho_{\mathrm{model}}[\ell]
=\frac{\overline R[\ell]}{\overline R[0]}.
$$

The script averages correlation estimates, not the noise waveforms. Averaging waveforms would suppress the random noise we are trying to characterize. Normalizing after averaging also differs from averaging 500 separately normalized curves: runs with greater realized noise power carry more weight in the supplied calculation.

For a single record, dividing its `biased` autocorrelation by its own zero-lag value gives the same result as `coeff`. The two code paths therefore use compatible scaling. [MathWorks: xcorr](https://www.mathworks.com/help/matlab/ref/xcorr.html)

The 500-run curve is a more stable estimate of what this fixed filter typically produces under the script's finite-record processing. Averaging reduces simulation-to-simulation fluctuations; it does not remove the uncertainty in the one measured test record, uncertainty in the fitted coefficients, or effects of finite-record mean removal. The measured curve is not expected to follow the model average exactly.

### Speaker notes: why this matters in a simulation

If noise samples reinforce one another, averaging may suppress them less effectively and integration may accumulate more error. Opposing deviations can partly cancel. The outcome depends on the correlation across the separations used by the downstream calculation.

For a simple sum of $M$ zero-mean stationary noise samples, this connection is explicit:

$$
\mathrm{Var}\!\left(\sum_{k=1}^{M}n[k]\right)
=M R_n[0]+2\sum_{\ell=1}^{M-1}(M-\ell)R_n[\ell].
$$

The first term is the contribution from individual-sample variance. The other terms account for relationships between samples. Matching RMS and autocorrelation therefore supports matching accumulated-error variance over the corresponding time intervals. A general linear downstream filter weights these relationships according to its own response. For an integration approximation, include the square of the time step. Keep this equation in the notes unless asked.

### Speaker notes: what counts as useful agreement

- Match the main decay, substantial peaks and troughs, and their positions over the relevant lag range. The two autocorrelations should agree with each other; they do not need to stay close to one.
- Small absolute differences near the extremes can be acceptable, especially where correlation is weak. A persistent separation or a missing substantial lobe deserves attention even near 2 seconds. The plot boundary alone does not make a difference unimportant.
- Judge absolute differences in normalized correlation. Percentage differences become misleading near zero. There is no universal tolerance; use record uncertainty and the time scales important to the simulation.
- If helpful, add the pointwise spread of the 500 individually normalized ACFs, such as their 2.5th to 97.5th percentiles. This shows variability expected for individual records under the fitted model. A narrow confidence interval for the model mean answers a different question. The spread is a useful reference, not a formal validation test against data used to fit that same model.
- Prefer the lowest order that captures the relevant residual ACF, residual PSD, and RMS. Increasing order solely to reproduce every feature of this one record can fit sampling fluctuations. In your script the same fitted tones are added to both full signals, so agreement of those tonal peaks alone does not establish that the stochastic filter is adequate.

When these quantities agree, the supported claim is that the generator reproduces the measured noise power and temporal dependence over the examined ranges. That is meaningful evidence for its use in simulation. Because the comparison uses the same residual used for identification, it establishes agreement with the fitted record; agreement on a separate record from the same regime would provide stronger evidence of generalization.

### Speaker notes: finite records and the ends of the plot

At lag $\ell$, only $N-|\ell|$ sample pairs overlap. Near the full record length, overlap can be very small and estimates become unreliable. The `biased` estimator divides by $N$ rather than the available pair count, which also attenuates long-lag estimates. [MathWorks: correlation and covariance](https://www.mathworks.com/help/signal/ug/correlation-and-covariance.html)

However, the end of your displayed range is not necessarily the end of the available record. At 80 Hz, 2 seconds is 160 samples. An illustrative 600-sample record still has 440 overlapping pairs there. Do not dismiss a mismatch at 2 seconds simply by calling it a long-lag effect. Products from colored noise can themselves be correlated, so 440 pairs also do not mean 440 independent observations.

Subtracting a finite record's estimated mean can shift autocorrelation estimates, including toward negative values. Your script mean-removes both the test residual and every model realization and uses equal lengths, keeping that processing consistent. Averaging 500 runs reduces random variation around the model's estimated curve; these finite-record effects can remain.

### Speaker notes: connection to Kasdin

Kasdin defines a criterion for simulating a continuous Gaussian process by requiring the discrete autocorrelation to equal samples of the continuous autocorrelation. See Section III-A, Definition 1, equation (41), printed page 808. For Gaussian processes, mean and covariance determine the joint distributions, explaining why matching noise level and temporal correlation is such a meaningful target. This does not establish that the measured sensor residual is Gaussian. [Kasdin, 1995](https://doi.org/10.1109/5.381848)

Our use is a discrete-data validation check inspired by that criterion: compare the temporal correlation in measured residual samples with the generated process. It supports the claim that the model represents the measured noise memory over the lag range examined.

For a stationary process, the true PSD and autocorrelation are Fourier-transform counterparts. They describe the same second-order statistics in frequency and time. In practice, Welch averaging can smooth spectral details whose effects are easier to notice as differences in autocorrelation. The ACF overlay makes the implied noise memory visible; it is a useful complement to the estimated PSD, not a mathematically independent test or proof of Kasdin's exact continuous-process criterion. [Kasdin, 1995](https://doi.org/10.1109/5.381848)

### Suggested spoken explanation

> The RMS tells me how large the random error is. Autocorrelation tells me how errors separated in time tend to reinforce or oppose each other. That matters because the vehicle model processes sequences of errors, and their relationship changes how they average out or accumulate. My shaping filter creates that relationship by carrying the influence of random inputs into later outputs. I compare its average autocorrelation over 500 independent runs with the measured residual's autocorrelation. If the important features agree away from zero lag, alongside PSD and RMS agreement, that supports the filter reproducing the measured noise behavior. The random samples can still differ on every run. I report the lag range actually supported by the plot, allowing for uncertainty in the finite test record.

---

## Reference material for speaker notes

- N. Jeremy Kasdin, "Discrete Simulation of Colored Noise and Stochastic Processes and $1/f^{\alpha}$ Power Law Noise Generation," *Proceedings of the IEEE*, vol. 83, no. 5, pp. 802–827, May 1995. [DOI: 10.1109/5.381848](https://doi.org/10.1109/5.381848). Relevant locations: Section II-C for PSD, its relationship to autocorrelation, and spectral estimation, and Section III-A for the simulation criterion.
- James Durbin, "The Fitting of Time-Series Models," Institute of Statistics, Mimeograph Series No. 244, December 1959. Supplied PDF. Section 2, equation (6), printed page 3 presents the equations using sample serial correlations.
- Project sources: the supplied `README.md`, the MATLAB identification script, `model_c_csv_loader(1).cpp`, and `Model_Correlation_v3.txt`. The runtime descriptions follow the supplied C++ file; slide 8's comparison details follow the validation script, including averaging autocorrelation estimates before normalization.
- [GitHub: Writing mathematical expressions](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/writing-mathematical-expressions). This guide uses dollar-delimited inline math and double-dollar display blocks with standard math commands. Upload the Markdown source directly so GitHub can render the equations.

The references and expanded speaker notes are preparation material, not additional required slides. Continue after slide 8 with your vehicle-simulation results.

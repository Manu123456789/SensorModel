
[test_derived_sensor_noise_model.md](https://github.com/user-attachments/files/31776632/test_derived_sensor_noise_model.md)
# Test-Derived Colored Sensor Noise Model

## Purpose

This document summarizes the development, simulation implementation, and validation of a test-derived sensor-error model. The complete model separates the measured signal into three components:

1. stationary bias;
2. deterministic tones; and
3. stochastic colored noise represented by an autoregressive (AR), or all-pole, filter.

For a model identified at sample rate $F_s$, the simulated sensor error is

$$
x_{\mathrm{model}}[k]
=
\mu_b
+
\sum_{j=1}^{N_t} A_j
\sin\!\left(2\pi f_j t_k+\phi_j\right)
+
n[k],
\qquad
t_k=\frac{k}{F_s},
$$

where $\mu_b$ is the stationary bias, $N_t$ is the number of explicit tones, and $n[k]$ is the stochastic output of the AR filter.

---

## 1. Model Development From Test Data

### 1.1 Select the operating regime

- Extract the portion of test data corresponding to the operating condition being modeled.
- Treat each operating regime separately because its bias, tones, and stochastic noise characteristics may differ.
- Use a segment that is approximately stationary and sufficiently long to represent the frequencies of interest.

The stationarity assumption applies within the selected regime. If the sensor statistics change significantly within the segment, one stationary model may not adequately represent the full interval.

### 1.2 Match the simulation sample rate

- Downsample the test data from the acquisition rate to the sensor-update rate used by the simulation.
- No anti-aliasing filter was applied in this implementation.

Direct decimation without anti-alias filtering allows content above the new Nyquist frequency to alias into the retained band. Consequently, the identified model represents the directly decimated signal used for this analysis, including any aliased content; it should not be interpreted as the unaliased spectrum of the original high-rate measurement.

### 1.3 Estimate and remove stationary bias

For a selected downsampled record $x_{\mathrm{DS}}[k]$ containing $N$ samples, estimate the stationary bias as

$$
\mu_b
=
\frac{1}{N}
\sum_{k=0}^{N-1}x_{\mathrm{DS}}[k].
$$

Remove the bias before identifying the tones and stochastic dynamics:

$$
x_0[k]=x_{\mathrm{DS}}[k]-\mu_b.
$$

The estimated bias is retained as a separate model parameter and restored when the complete sensor-error signal is assembled.

### 1.4 Identify the dominant tonal frequencies

- Compute the FFT of the de-biased data to locate persistent narrowband peaks.
- Use the PSD as supporting evidence that the selected peaks rise above the surrounding stochastic background.
- Select the frequencies that represent deterministic or repeatable tonal behavior.

The FFT provides candidate tone frequencies. It does not, by itself, completely determine the amplitude and phase of each sinusoid.

### 1.5 Fit tone amplitudes and phases

At the selected frequencies, fit sine and cosine basis functions to the de-biased data using least squares. The explicit tone model is

$$
x_{\mathrm{tone}}[k]
=
\sum_{j=1}^{N_t} A_j
\sin\!\left(2\pi f_j t_k+\phi_j\right).
$$

The fitted sine and cosine coefficients are converted into the amplitude $A_j$ and phase $\phi_j$ of each tone. Fitting all selected tones simultaneously reduces interference between the individual tone estimates.

### 1.6 Construct the stochastic residual

Remove the stationary bias and fitted tone model from the downsampled measurement:

$$
r[k]
=
x_{\mathrm{DS}}[k]
-
\mu_b
-
x_{\mathrm{tone}}[k].
$$

The result $r[k]$ is the **stochastic residual** used for AR identification. It is the portion of the measurement assigned to the stochastic model, although it may still contain unmodeled tones, drift, or measurement artifacts.

### 1.7 Select the AR model order

An AR model order of

$$
p=20
$$

was selected using approximately 600 test samples. This provides approximately

$$
\frac{N}{p}=\frac{600}{20}=30
$$

samples per estimated lag coefficient.

The commonly cited samples-per-parameter ratio is only an informal screening heuristic, not a universal model-order rule. The principal justification for $p=20$ is that it is conservative relative to the available record length and provides good agreement with the measured PSD, RMS, and autocorrelation without unnecessary filter complexity.

### 1.8 Fit the AR model using the Yule-Walker equations

Represent the stochastic residual using an order-$p$ autoregressive model:

$$
r[k]
+
\sum_{i=1}^{p} a_i r[k-i]
=
e[k],
$$

where $e[k]$ is a zero-mean white innovation sequence with variance $\sigma_e^2$.

The Yule-Walker equations estimate the AR coefficients from the autocorrelation of the measured residual. In MATLAB, the model is obtained using

```matlab
[aNoise, noiseVar] = aryule(residual, noiseOrder);
bNoise = sqrt(noiseVar);
```

The returned denominator coefficient vector is

$$
\mathbf{a}
=
\begin{bmatrix}
a_0 & a_1 & \cdots & a_p
\end{bmatrix},
\qquad a_0=1,
$$

and the white-noise input gain is

$$
b_{\mathrm{noise}}=\sqrt{\sigma_e^2}.
$$

The corresponding all-pole shaping filter is

$$
H(z)
=
\frac{b_{\mathrm{noise}}}
{a_0+\displaystyle\sum_{i=1}^{p}a_i z^{-i}}.
$$

The denominator coefficients establish the spectral coloring and temporal correlation, while $b_{\mathrm{noise}}$ establishes the appropriate innovation magnitude. Both are required to reproduce the residual noise power correctly.

### 1.9 Store the identified model

For each operating regime, retain the following parameters:

- sample rate $F_s$;
- stationary bias $\mu_b$;
- tone frequencies $f_j$;
- tone amplitudes $A_j$;
- tone phases $\phi_j$;
- AR denominator coefficients $a_0,\ldots,a_p$; and
- innovation gain $b_{\mathrm{noise}}$.

This parameter set completely defines the test-derived sensor-error model for the selected operating regime.

---

## 2. Simulation Implementation

### 2.1 Import the identified parameters

The simulation receives the test-derived AR coefficients, innovation gain, tone parameters, bias, and sample rate. For a 20th-order model:

- 20 lag coefficients are estimated;
- 20 previous stochastic outputs must be retained; and
- the denominator array contains 21 values when the leading coefficient $a_0$ is included.

The modeled sensor signal and the simulation injection point must use the same units, sample rate, and signal definition.

### 2.2 Maintain persistent AR-filter memory

The AR recursion requires the previous $p$ stochastic filter outputs:

$$
n[k-1],\ n[k-2],\ \ldots,\ n[k-p].
$$

These history values must persist between sensor-update calls. In C or C++, this can be implemented as persistent object state or as a mutable `static` history buffer when there is only one applicable sensor instance. Each independently simulated sensor must have its own history.

If the history were reset during every update, the filter would repeatedly restart and would not reproduce the identified colored spectrum or temporal correlation. Zero initialization also creates a startup transient; when the initial interval matters, the filter should be warmed up before validation data are collected.

### 2.3 Generate the white stochastic excitation

At each sensor update, use the existing random-number generator to produce an independent unit-Gaussian sample:

$$
w[k]\sim\mathcal{N}(0,1).
$$

This is a time-varying stochastic excitation, not static noise. The sample is multiplied by $b_{\mathrm{noise}}$ before entering the AR recursion.

### 2.4 Compute the colored stochastic output

Implement the all-pole filter using

$$
n[k]
=
\frac{
b_{\mathrm{noise}}w[k]
-
\displaystyle\sum_{i=1}^{p}a_i n[k-i]
}{a_0}.
$$

For coefficients produced by MATLAB `aryule`, $a_0=1$. Retaining the division by $a_0$ nevertheless implements the complete transfer-function definition and avoids relying on an implicit normalization assumption.

The feedback contribution from the stored outputs creates the spectral coloring and temporal memory of the modeled stochastic process.

### 2.5 Update the AR history

After computing $n[k]$:

1. shift the stored stochastic outputs by one position, beginning with the oldest index to avoid overwriting required values; and
2. save $n[k]$ as the newest history sample.

The stored value is the current **AR colored-noise output**. It is not the original test residual and it is not the complete sensor error containing bias and tones.

### 2.6 Generate the deterministic tones

At every update, evaluate the tone model using the current simulation time:

$$
x_{\mathrm{tone}}(t)
=
\sum_{j=1}^{N_t} A_j
\sin\!\left(2\pi f_j t+\phi_j\right).
$$

The simulation time must be expressed in seconds and remain continuous between calls. The tone parameters may be stored as constants, but the instantaneous tone signal is recalculated from time and is not included in the AR history.

#### Why the tones are excluded from the AR history

The AR model was identified from the stochastic residual after the tones were removed. Its state must therefore contain only the stochastic AR output. Feeding the tones back through the AR history would:

- filter the tones a second time;
- alter their fitted amplitudes and phases;
- potentially amplify them near AR resonances;
- contaminate the stochastic filter state; and
- double-count deterministic tonal behavior.

The explicit tones are external deterministic components and are added only after the stochastic AR output has been generated.

### 2.7 Assemble the complete sensor-frame error

Combine the three model components in the sensor frame:

$$
e_2[k]
=
\mu_b
+
x_{\mathrm{tone}}[k]
+
n[k].
$$

For a model identified on the second sensor axis, form

$$
\mathbf{e}_{\mathrm{sensor}}[k]
=
\begin{bmatrix}
0\\
e_2[k]\\
0
\end{bmatrix}.
$$

If the bias is already applied through an existing simulation path, it must not be added a second time.

### 2.8 Transform the error into the platform frame

Apply the established sensor-to-platform rotation:

$$
\mathbf{e}_{\mathrm{platform}}[k]
=
\mathbf{R}_{\mathrm{sensor}\rightarrow\mathrm{platform}}
\mathbf{e}_{\mathrm{sensor}}[k].
$$

In the current implementation, this conversion is performed using the transpose of the stored transformation matrix, consistent with the existing frame convention. Combining the bias, tones, and colored noise before the transformation ensures that the complete sensor-frame error is rotated consistently.

### 2.9 Inject the modeled error

The transformed error is passed through the existing downstream sensor path. The original white-noise injection is replaced or bypassed so that stochastic noise is not counted twice. All other downstream processing remains unchanged unless required by the sensor signal definition.

The per-update implementation sequence is therefore:

1. generate a unit-Gaussian innovation;
2. compute the AR colored-noise output;
3. update the AR history;
4. evaluate the explicit tones using simulation time;
5. add the bias, tones, and colored noise in the sensor frame;
6. rotate the complete error into the platform frame; and
7. inject it through the existing sensor path.

---

## 3. Model Validation

### 3.1 Perform like-for-like comparisons

Two related comparisons serve different purposes:

1. Compare the AR-generated stochastic noise $n[k]$ with the test stochastic residual $r[k]$. This isolates validation of the identified AR filter.
2. Compare the complete simulated error with the complete processed test signal. This validates the combined bias, explicit tones, and stochastic noise implementation.

This distinction prevents deterministic tone energy from being incorrectly attributed to the AR filter.

Because the simulated stochastic sequence is an independent random realization, it is not expected to reproduce the measured signal sample by sample. The objective is agreement in the relevant statistical properties.

### 3.2 Compare power spectral densities

Estimate the PSDs of the measured and simulated signals using the same:

- sample rate;
- record length, where practical;
- window and segment settings; and
- frequency units and PSD normalization.

Confirm agreement in:

- broadband spectral shape;
- overall noise-floor level;
- dominant frequency content; and
- tone frequencies and levels for the complete model.

PSD agreement demonstrates that the model reproduces how the measured signal power is distributed across frequency.

### 3.3 Compare broadband noise RMS

For a zero-mean signal with a one-sided PSD $S_{xx}(f)$, the variance over the modeled band is

$$
\sigma_x^2
=
\int_{0}^{F_s/2} S_{xx}(f)\,df,
$$

and the broadband noise RMS is

$$
\mathrm{RMS}_{\mathrm{noise}}
=
\sigma_x
=
\sqrt{
\int_{0}^{F_s/2} S_{xx}(f)\,df
}.
$$

This should be described as the **broadband noise RMS over the modeled bandwidth**. Agreement confirms that the model reproduces the total fluctuating noise power, while the PSD comparison confirms how that power is distributed across frequency.

If a nonzero bias is retained, the total signal RMS is different from the zero-mean noise RMS:

$$
\mathrm{RMS}_{\mathrm{total}}
=
\sqrt{\mu_b^2+\sigma_x^2}.
$$

Accordingly, the signal must be de-biased when the intended comparison is specifically the stochastic noise RMS.

### 3.4 Compare autocorrelation

For a zero-mean stationary process, the autocorrelation is

$$
R_{xx}[\ell]
=
\operatorname{E}\!\left\{x[k]x[k-\ell]\right\}.
$$

The normalized autocorrelation is

$$
\rho_{xx}[\ell]
=
\frac{R_{xx}[\ell]}{R_{xx}[0]}.
$$

Compare the measured and modeled autocorrelation over physically relevant time lags. The decay rate, oscillations, and characteristic lag structure describe how strongly successive samples are related and therefore reveal the temporal memory of the colored noise.

Using normalized autocorrelation isolates the correlation shape, while the separate RMS comparison validates its magnitude. At zero lag,

$$
R_{xx}[0]=\sigma_x^2
$$

for a zero-mean stationary process.

### 3.5 Interpret the PSD and autocorrelation together

For a wide-sense stationary discrete process, the PSD and autocorrelation are related by the discrete-time Wiener-Khinchin relation:

$$
S_{xx}\!\left(e^{j\omega}\right)
=
\sum_{\ell=-\infty}^{\infty}
R_{xx}[\ell]e^{-j\omega\ell}.
$$

Therefore, PSD and autocorrelation are not completely independent validation quantities. They are complementary representations of the same second-order statistics:

- the PSD provides the clearest view of frequency-dependent noise power; and
- the autocorrelation provides the clearest view of temporal dependence and memory.

Autocorrelation should therefore be described as a complementary time-lag confirmation of the temporal structure implied by the colored-noise spectrum, rather than as a mathematically independent test.

### 3.6 Account for finite-record variation

With approximately 600 samples, some difference between measured and simulated estimates is expected because:

- the simulated signal is an independent stochastic realization;
- PSD and autocorrelation estimates have finite-sample uncertainty; and
- autocorrelation estimates become less reliable at longer lags because fewer sample pairs contribute.

The validation objective is close statistical agreement over the frequency band and time-lag range relevant to the simulation, not exact point-by-point agreement.

### 3.7 Validation conclusion

The validation supports the following conclusion:

> The simulation reproduces the measured broadband noise level, dominant spectral content, and temporal correlation structure. The identified model therefore captures the principal second-order statistical characteristics of the measured sensor error.

For a Gaussian stochastic residual, matching the mean and second-order statistics characterizes the modeled stochastic process. The deterministic tones are validated separately through their fitted frequencies, amplitudes, and phases.

---

## References

1. N. Jeremy Kasdin, "Discrete Simulation of Colored Noise and Stochastic Processes and $1/f^{\alpha}$ Power Law Noise Generation," *Proceedings of the IEEE*, vol. 83, no. 5, pp. 802-827, May 1995, doi: `10.1109/5.381848`.

   Kasdin provides the stochastic-simulation framework, discusses the relationship between autocorrelation and autospectral density, describes recursive AR noise generation, and notes that ARMA coefficients can be identified from measured autocorrelation through the Yule-Walker equations.

2. James Durbin, "The Fitting of Time-Series Models," Institute of Statistics, Mimeograph Series No. 244, December 1959.

   Durbin reviews the fitting of autoregressive models from sample serial correlations and develops the recursive coefficient-estimation relationships associated with AR time-series modeling.

---

## Condensed Presentation Summary

### Model development

- Select an approximately stationary operating regime and downsample it to the simulation rate.
- Estimate and remove the stationary bias.
- Identify dominant tone frequencies using the FFT and fit their amplitudes and phases using least squares.
- Subtract the tone model to obtain the stochastic residual.
- Fit a 20th-order all-pole AR model to the residual using the Yule-Walker equations.
- Retain the AR coefficients, innovation gain, bias, tone parameters, and sample rate for the selected regime.

### Simulation implementation

- Drive the AR filter with unit-Gaussian white innovations.
- Maintain 20 previous stochastic outputs as persistent filter state.
- Keep deterministic tones outside the AR history and calculate them directly from simulation time.
- Add the bias, tones, and colored stochastic output in the sensor frame.
- Transform the complete error into the platform frame and inject it through the existing sensor path.

### Validation

- Compare the AR output with the measured stochastic residual and compare the complete simulated error with the complete processed test signal.
- Use PSD agreement to validate spectral shape, total noise level, and dominant frequency content.
- Use integrated PSD to compare broadband noise RMS.
- Use autocorrelation to confirm the corresponding temporal dependence and memory.
- Interpret PSD and autocorrelation as complementary views of the same second-order statistics.

# FFT-Based Tone Identification and Least-Squares Amplitude/Phase Estimation

## Purpose

This document explains the deterministic tone-identification portion of the sensor-error modeling process. In this implementation, the **FFT is used to select candidate tone frequencies**, and then **least squares estimates the amplitude and phase of all selected tones simultaneously**.

The key MATLAB implementation is

```matlab
H = zeros(L,2*n);
for j = 1:n
    H(:,2*j-1) = sin(2*pi*toneFreq(j)*t);
    H(:,2*j)   = cos(2*pi*toneFreq(j)*t);
end

beta = H\x0;
fittedTone = H*beta;
```

The overall goal is to represent the de-biased measured signal using a finite sum of deterministic sinusoids,

$$
x_0(t) \approx \sum_{j=1}^{N_t} A_j\sin\!\left(2\pi f_j t+\phi_j\right),
$$

where the frequencies $f_j$ have already been selected from the FFT, while the amplitudes $A_j$ and phases $\phi_j$ are estimated using least squares.

---

## 1. Candidate Frequencies Are Selected First

Before the least-squares step, the FFT and peak-selection logic produce the vector

```matlab
toneFreq
```

containing the candidate deterministic tone frequencies.

For example, if three dominant tones are selected, then

$$
f_1,\qquad f_2,\qquad f_3
$$

are treated as known frequencies during the least-squares fit.

At this stage, **frequency is no longer an unknown in the fit**. The least-squares calculation determines how much sine and cosine content at each selected frequency is required to reproduce the measured signal as closely as possible.

The desired multi-tone representation is

$$
x_0(t) \approx A_1\sin\!\left(2\pi f_1t+\phi_1\right)
+A_2\sin\!\left(2\pi f_2t+\phi_2\right)
+A_3\sin\!\left(2\pi f_3t+\phi_3\right).
$$

The same formulation extends directly to any number of selected tones $N_t$.

---

## 2. Rewrite Each Tone in Linear Form

For one tone, the physical amplitude-phase representation is

$$
A\sin(\omega t+\phi).
$$

Directly fitting both $A$ and $\phi$ would make the parameterization nonlinear. Instead, use the trigonometric identity

$$
\sin(\omega t+\phi)
=
\sin(\omega t)\cos\phi
+
\cos(\omega t)\sin\phi.
$$

Multiplying by $A$ gives

$$
A\sin(\omega t+\phi)
=
A\cos\phi\,\sin(\omega t)
+
A\sin\phi\,\cos(\omega t).
$$

Define

$$
a=A\cos\phi,
\qquad
b=A\sin\phi.
$$

Then the tone becomes

$$
A\sin(\omega t+\phi)
=
a\sin(\omega t)+b\cos(\omega t).
$$

The important result is that the new unknown coefficients $a$ and $b$ appear **linearly**. Therefore, ordinary linear least squares can be used.

For tone $j$,

$$
x_j(t)
=
a_j\sin(2\pi f_jt)+b_j\cos(2\pi f_jt).
$$

---

## 3. Construct the Sine/Cosine Basis Matrix

The MATLAB code

```matlab
H = zeros(L,2*n);
for j = 1:n
    H(:,2*j-1) = sin(2*pi*toneFreq(j)*t);
    H(:,2*j)   = cos(2*pi*toneFreq(j)*t);
end
```

constructs a matrix containing the candidate sinusoidal waveforms evaluated over the complete data record.

For each selected frequency $f_j$, two columns are created:

1. a sine basis function;
2. a cosine basis function.

If three tones are selected, the matrix has the conceptual form

$$
\mathbf{H}
=
\begin{bmatrix}
\sin(2\pi f_1t_1) & \cos(2\pi f_1t_1) &
\sin(2\pi f_2t_1) & \cos(2\pi f_2t_1) &
\sin(2\pi f_3t_1) & \cos(2\pi f_3t_1)
\\
\sin(2\pi f_1t_2) & \cos(2\pi f_1t_2) &
\sin(2\pi f_2t_2) & \cos(2\pi f_2t_2) &
\sin(2\pi f_3t_2) & \cos(2\pi f_3t_2)
\\
\vdots & \vdots & \vdots & \vdots & \vdots & \vdots
\end{bmatrix}.
$$

For $L$ measured samples and $N_t$ selected tones,

$$
\mathbf{H}\in\mathbb{R}^{L\times 2N_t}.
$$

The unknown coefficient vector is

$$
\boldsymbol{\beta}
=
\begin{bmatrix}
a_1 & b_1 & a_2 & b_2 & \cdots & a_{N_t} & b_{N_t}
\end{bmatrix}^{T}.
$$

The measurement model can therefore be written compactly as

$$
\mathbf{x}_0 \approx \mathbf{H}\boldsymbol{\beta}.
$$

Each pair of columns in $\mathbf{H}$ can be interpreted as:

> The sine and cosine waveforms that would exist over the entire test record if a tone were present at this FFT-selected frequency.

Because the number of measured samples $L$ is normally much larger than the number of unknown coefficients $2N_t$, the problem is typically strongly overdetermined.

---

## 4. Solve the Simultaneous Least-Squares Problem

The MATLAB statement

```matlab
beta = H\x0;
```

solves the least-squares problem

$$
\hat{\boldsymbol{\beta}}
=
\underset{\boldsymbol{\beta}}{\operatorname{argmin}}
\left\|\mathbf{H}\boldsymbol{\beta}-\mathbf{x}_0\right\|_2^2.
$$

In words:

> Find the combination of the selected sine and cosine basis functions that minimizes the total squared error between the reconstructed tone signal and the measured de-biased data over the complete record.

For three selected tones,

$$
\boldsymbol{\beta}
=
\begin{bmatrix}
a_1\\
b_1\\
a_2\\
b_2\\
a_3\\
b_3
\end{bmatrix}.
$$

The corresponding fitted signal is

$$
\mathbf{H}\boldsymbol{\beta}
=
a_1\sin(2\pi f_1t)+b_1\cos(2\pi f_1t)
+\cdots+
a_3\sin(2\pi f_3t)+b_3\cos(2\pi f_3t).
$$

The MATLAB statement

```matlab
fittedTone = H*beta;
```

therefore generates the **best-fit deterministic multi-tone component** of the measured data at the selected frequencies.

---

## 5. Why Both Sine and Cosine Are Required

A single sine basis function cannot represent an arbitrary phase shift at a fixed frequency.

For example, suppose the actual measured tone is

$$
4\sin\!\left(2\pi(10)t+0.7\right).
$$

If the model included only

```matlab
sin(2*pi*10*t)
```

then it could change the amplitude, but it could not independently reproduce the phase offset of $0.7$ rad.

By using both

$$
\sin(\omega t)
\qquad\text{and}\qquad
\cos(\omega t),
$$

any phase at that frequency can be represented as

$$
a\sin(\omega t)+b\cos(\omega t).
$$

Least squares determines the required sine coefficient $a$ and cosine coefficient $b$, which can then be converted back into the more intuitive amplitude-phase form.

---

## 6. Recover the Tone Amplitude

After solving for `beta`, the coefficients associated with tone $j$ are extracted as

```matlab
a = beta(2*j-1);
b = beta(2*j);
```

From the definitions

$$
a=A\cos\phi,
\qquad
b=A\sin\phi,
$$

we have

$$
a^2+b^2
=
A^2\cos^2\phi+A^2\sin^2\phi.
$$

Using

$$
\cos^2\phi+\sin^2\phi=1,
$$

gives

$$
a^2+b^2=A^2.
$$

Therefore,

$$
\boxed{A=\sqrt{a^2+b^2}}.
$$

The MATLAB implementation is

```matlab
toneAmp(j) = hypot(a,b);
```

Thus, `toneAmp(j)` is the least-squares estimate of the amplitude of the $j$th selected tone.

---

## 7. Recover the Tone Phase

Again using

$$
a=A\cos\phi,
\qquad
b=A\sin\phi,
$$

we obtain

$$
\frac{b}{a}=\tan\phi.
$$

Conceptually,

$$
\phi=\tan^{-1}\!\left(\frac{b}{a}\right).
$$

In practice, MATLAB uses

```matlab
tonePhase(j) = atan2(b,a);
```

because `atan2` determines the correct angular quadrant and handles cases where $a$ is zero or near zero more robustly.

Therefore,

$$
\boxed{\phi=\operatorname{atan2}(b,a)}.
$$

The two tone representations are consequently equivalent:

$$
\boxed{
a_j\sin(2\pi f_jt)+b_j\cos(2\pi f_jt)
=
A_j\sin\!\left(2\pi f_jt+\phi_j\right)
}
$$

with

$$
A_j=\sqrt{a_j^2+b_j^2},
\qquad
\phi_j=\operatorname{atan2}(b_j,a_j).
$$

---

## 8. All Selected Tones Are Fitted Simultaneously

An important feature of this implementation is that the selected tones are **not fitted one at a time**.

The algorithm does not perform

```text
fit tone 1
subtract tone 1
fit tone 2
subtract tone 2
fit tone 3
...
```

Instead, all selected sine and cosine basis functions are included in the same matrix $\mathbf{H}$, and the code solves one simultaneous problem:

$$
\boxed{
\mathbf{x}_0\approx\mathbf{H}\boldsymbol{\beta}
}
$$

or, equivalently,

$$
\boxed{
\hat{\boldsymbol{\beta}}
=
\underset{\boldsymbol{\beta}}{\operatorname{argmin}}
\left\|\mathbf{H}\boldsymbol{\beta}-\mathbf{x}_0\right\|_2^2
}.
$$

This allows the least-squares solution to distribute the measured signal among all selected tone frequencies in the combination that minimizes the total squared reconstruction error.

This is particularly useful when:

- multiple tones are relatively close in frequency;
- the data record is finite;
- spectral leakage causes energy from one physical tone to appear in neighboring FFT bins; or
- the candidate basis functions are not perfectly orthogonal over the available record length.

A simultaneous fit reduces the dependence of the result on the order in which individual tones would otherwise be estimated and subtracted.

---

## 9. Reconstruct the Deterministic Tone Model

After the amplitude and phase of each selected tone have been recovered, the deterministic tone model can be written as

$$
\boxed{
x_{\mathrm{tone}}(t)
=
\sum_{j=1}^{N_t}
A_j\sin\!\left(2\pi f_jt+\phi_j\right)
}.
$$

This is equivalent to the direct least-squares reconstruction

$$
x_{\mathrm{tone}}=\mathbf{H}\hat{\boldsymbol{\beta}}.
$$

In MATLAB,

```matlab
fittedTone = H*beta;
```

produces the deterministic component directly in the sine/cosine basis representation.

The amplitude-phase parameters can then be stored separately for later reconstruction inside the simulation.

---

## 10. Construct the Stochastic Residual

The complete measured signal is first de-biased:

$$
x_0[k]=x_{\mathrm{test}}[k]-\mu_b.
$$

After fitting the deterministic tones, the residual is

$$
\boxed{
r[k]=x_0[k]-x_{\mathrm{tone}}[k]
}.
$$

Equivalently,

$$
r[k]
=
x_{\mathrm{test}}[k]-\mu_b-x_{\mathrm{tone}}[k].
$$

This residual contains the portion of the test signal not explained by the stationary bias or the explicit deterministic tones.

In the broader sensor-error architecture, this residual can then be modeled using either:

- a colored stochastic model such as AR or ARMA; or
- a simpler Gaussian white-noise model if the residual is sufficiently spectrally flat and temporally uncorrelated for the intended application.

---

## 11. Complete Identification Architecture

The tone-identification workflow can be summarized as

```text
measured test signal
        |
        v
estimate and remove stationary bias
        |
        v
compute FFT / PSD
        |
        v
select candidate tone frequencies
        |
        v
construct sine/cosine basis matrix H
        |
        v
solve beta = H\x0
        |
        v
recover amplitude and phase
        |
        v
construct deterministic tone model
        |
        v
subtract tone model from de-biased data
        |
        v
stochastic residual
```

Mathematically, the principal steps are

$$
x_0[k]=x_{\mathrm{test}}[k]-\mu_b,
$$

followed by FFT-based selection of

$$
f_1,f_2,\ldots,f_{N_t},
$$

then the simultaneous least-squares fit

$$
\hat{\boldsymbol{\beta}}
=
\underset{\boldsymbol{\beta}}{\operatorname{argmin}}
\left\|\mathbf{H}\boldsymbol{\beta}-\mathbf{x}_0\right\|_2^2,
$$

followed by

$$
A_j=\sqrt{a_j^2+b_j^2},
\qquad
\phi_j=\operatorname{atan2}(b_j,a_j),
$$

and finally

$$
x_{\mathrm{tone}}(t)
=
\sum_{j=1}^{N_t}
A_j\sin\!\left(2\pi f_jt+\phi_j\right).
$$

The stochastic residual is then

$$
\boxed{
r[k]=x_0[k]-x_{\mathrm{tone}}[k]
}.
$$

---

## 12. Important Limitation: Least Squares Does Not Refine Frequency

The least-squares step estimates the sine and cosine coefficients only at the frequencies already contained in

```matlab
toneFreq
```

Therefore, it refines:

- tone amplitude; and
- tone phase;

but it does **not** refine the tone frequency itself.

If the FFT selects a frequency $f_j$ that differs slightly from the true physical tone frequency $f_j^{\ast}$, then least squares finds the best amplitude and phase possible at the fixed selected frequency $f_j$.

It does not solve

$$
\min_{A_j,\phi_j,f_j}
\left\|
A_j\sin(2\pi f_jt+\phi_j)-x_0(t)
\right\|_2^2.
$$

Instead, it solves the linear problem with $f_j$ held fixed.

This matters because the FFT frequency resolution is determined by the record length. For a record containing $L$ samples at sample rate $F_s$,

$$
\Delta f=\frac{F_s}{L}.
$$

A physical tone lying between FFT bins may therefore be represented by the nearest selected bin rather than its exact underlying frequency. Possible symptoms include:

- a small offset between the reconstructed and measured tone peak;
- residual energy near the fitted tone;
- a broader-looking peak in the PSD; or
- apparent spectral leakage around the deterministic tone.

If these effects become important, a subsequent nonlinear frequency-refinement step can be added. However, for the current simplified architecture, the FFT-selected-frequency plus simultaneous least-squares amplitude/phase fit provides a compact and computationally straightforward deterministic tone model.

---

## Condensed Summary

- Remove the stationary bias from the measured record.
- Use the FFT/PSD to identify candidate deterministic tone frequencies.
- Treat those frequencies as fixed during the least-squares fit.
- For each frequency, create both sine and cosine basis functions.
- Assemble all basis functions into one matrix $\mathbf{H}$.
- Solve

$$
\hat{\boldsymbol{\beta}}
=
\underset{\boldsymbol{\beta}}{\operatorname{argmin}}
\left\|\mathbf{H}\boldsymbol{\beta}-\mathbf{x}_0\right\|_2^2.
$$

- Convert each fitted sine/cosine coefficient pair into amplitude and phase using

$$
A_j=\sqrt{a_j^2+b_j^2},
\qquad
\phi_j=\operatorname{atan2}(b_j,a_j).
$$

- Reconstruct the deterministic signal as

$$
x_{\mathrm{tone}}(t)
=
\sum_{j=1}^{N_t}A_j\sin\!\left(2\pi f_jt+\phi_j\right).
$$

- Subtract the fitted tone model from the de-biased measurement to obtain the stochastic residual.
- All selected tones are fitted simultaneously, which avoids sequential tone-subtraction effects.
- The least-squares stage refines amplitude and phase, but the selected frequencies remain fixed at the FFT-derived values unless an additional frequency-refinement procedure is introduced.

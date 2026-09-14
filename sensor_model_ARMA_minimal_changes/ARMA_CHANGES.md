**ARMA conversion — minimal edits to your original files**

The complete edited files retain the original section order and existing variable names. Every functional edit is labeled `ARMA CHANGE` in the source. The accompanying `ARMA_minimal_changes.diff` shows the exact removed and added lines against your originals. In that file, `-` means remove the old line, `+` means add the new line, and unprefixed context locates the edit. Do not type the diff prefixes. Comments and blank lines are optional when entering edits manually.

| Original used | Complete edited copy |
| --- | --- |
| `sensor_model_from_test_per_regime_csv(2).m` — your Burg version | `sensor_model_from_test_per_regime_ARMA_minimal.m` |
| `model_c_csv_loader(1).cpp` — your per-regime loader and sensor function | `model_c_csv_loader_ARMA_minimal.cpp` |
| `Model_Correlation_v3.txt` — your 500-realization version | `Model_Correlation_ARMA_minimal.m` |

These are separate ARMA copies. The previous ARMA files from the earlier conversation are not the source of this edit.

**MATLAB identification: M1–M3**

M1: Keep `noiseOrder` as the denominator order and add one numerator-order setting:

```matlab
noiseOrder = 10;
noiseMAOrder = 4;
```

This configures ARMA(10,4): 11 entries in `noiseA`, including its leading 1, and 5 entries in `noiseB`. The existing denominator setting remains 10; the new numerator setting is a starting value, not an order selected from your measurements.

M2: Replace the old `arburg` or `aryule` call and `bNoise = sqrt(noiseVar)` with:

```matlab
model = armax(iddata(residual,[],1/Fs), ...
    [noiseOrder noiseMAOrder], ...
    armaxOptions('EnforceStability',true));

aNoise = model.A;
noiseVar = model.NoiseVariance;
bNoise = sqrt(noiseVar)*model.C;

assert(all(abs(roots(aNoise)) < 1), ...
    'ARMA noise model must have all poles inside the unit circle.');
```

This requires **System Identification Toolbox**, in addition to the toolboxes already used by your scripts. `armax` estimates an ARMA time-series model when the input channel is empty and the orders are `[na nc]`. Its noise numerator is `model.C`; its `model.B` is the measured-input polynomial and is empty here. [MathWorks: armax](https://www.mathworks.com/help/ident/ref/armax.html), [MathWorks: idpoly](https://www.mathworks.com/help/ident/ref/idpoly.html)

The existing storage lines remain exactly the same:

```matlab
sensorModel(i).noiseA   = aNoise;
sensorModel(i).noiseB   = bNoise;
sensorModel(i).noiseVar = noiseVar;
```

`noiseVar` is the fitted white-innovation variance. Multiplying the entire `model.C` by `sqrt(noiseVar)` makes the stored filter suitable for **unit-variance** white input. Apply that gain once. Both MATLAB and C++ use the scaled coefficients directly. The resulting filter is `noiseB(z)/noiseA(z)`. [MathWorks: innovation variance](https://www.mathworks.com/help/ident/ref/idpoly.html)

M3: Replace the scalar `noiseB` print statement with the same vector display pattern already used for `noiseA`:

```matlab
fprintf('noiseB = [')
fprintf(' %.12g',bNoise)
fprintf(' ]\n')
```

This display edit is optional for execution. Use the CSV for transferring coefficients; the console display retains your original 12-significant-digit formatting.

**CSV export: M4–M5**

The scalar numerator column must change because ARMA has several numerator coefficients. Keep the first seven column names and positions; append `ma_order` at the end:

| Column | Name | Contents |
| --- | --- | --- |
| 1 | `filter_order` | Denominator order `p`, repeated |
| 2 | `number_of_tones` | Tone count, repeated |
| 3 | `tone_frequency` | Existing tone frequencies, then padding |
| 4 | `tone_amplitude` | Existing tone amplitudes, then padding |
| 5 | `tone_phase` | Existing tone phases, then padding |
| 6 | `noise_model_A` | `a0` through `ap`, then padding |
| 7 | `noise_model_B` | Scaled `b0` through `bq`, then padding |
| 8 | `ma_order` | Numerator order `q`, repeated |

M4 is localized to the export-loop setup:

- Add `ma_order = length(model.noiseB)-1;` next to `filter_order`.
- Replace `nRows` and the old “more tones than rows” error block with `nRows = max([length(model.noiseA),length(model.noiseB),number_of_tones]);`.
- Add `noise_model_B = nan(nRows,1);` next to the existing A allocation.
- Add `noise_model_B(1:length(model.noiseB)) = model.noiseB(:);` next to the existing A assignment.
- Replace `noise_model_B = repmat(model.noiseB,nRows,1);` with `ma_order_col = repmat(ma_order,nRows,1);`.

M5 adds `ma_order_col` immediately after `noise_model_B` in the `table(...)` data arguments, and `'ma_order'` immediately after `'noise_model_B'` in `VariableNames`. The source and diff show the exact commas and continuation markers.

The existing per-regime filenames and `writetable` call remain the same. Point `outputDirectory` to the directory for your ARMA copy and use that same directory in C++. Regenerate the CSVs before running the updated loader. It requires the new eighth column and rejects the previous seven-column files. A newly exported `ma_order = 0` model still works as an AR filter.

**C++ loader and recurrence: C1–C8**

Every edit is marked at its insertion or replacement point in the complete C++ file. These are the required locations:

| Marker | Location | Edit |
| --- | --- | --- |
| C1 | `SensorNoiseModel` | Add `int ma_order = 0;`; change `noise_model_B` from `double` to `std::vector<double>`. |
| C2 | First-row CSV handling | Require 8 columns; read `ma_order` from `field[7]` instead of reading a scalar B from `field[6]`. Reject negative orders/counts. |
| C3 | Coefficient reading | Read A from `field[5]` only when `row <= filter_order`; read B from `field[6]` only when `row <= ma_order`. Ignore padding outside each array's length. |
| C4 | Loader checks | Check the B length, finite A/B values, and nonzero `A[0]` before filtering. |
| C5 | Existing coefficient aliases | Keep `noise_model_b`, now as a vector reference; add `noise_model_ma_order`. |
| C6 | Filter memory | Keep `noise_model_history` for previous outputs; add `noise_model_input_history` for previous white inputs. |
| C7 | Stochastic output calculation | Use `noise_model_b[0]` for the current input and add the B-weighted previous inputs. |
| C8 | Memory update | Shift and save the white input after computing the current output. |

The recurrence now implements

\[
y[k]=\frac{b_0w[k]+\sum_{j=1}^{q}b_jw[k-j]
-\sum_{i=1}^{p}a_iy[k-i]}{a_0}.
\]

`sensor_axis2_ar_noise` keeps its original name. The existing A-feedback loop, division by `noise_model_a[0]`, output-history update, tone generation, and measurement integration remain in their original positions. The input history stores the **unscaled white samples**, while the output history stores the **stochastic filter output before adding tones**. [MathWorks: filter difference equation](https://www.mathworks.com/help/matlab/ref/filter.html)

**500-realization validation: V1 only**

Only one executable line changes:

```matlab
burnIn = max(10*(max(length(model.noiseA),length(model.noiseB))-1),round(5*Fs));
```

This extends your existing burn-in heuristic to account for the longer polynomial if the MA order exceeds the AR order. For the supplied `(10,4)` orders it gives the same burn-in as before. It is a heuristic; very slowly decaying poles can need a longer transient exclusion.

Your existing call already supports the full numerator vector:

```matlab
arTemp = filter(model.noiseB,model.noiseA,w);
```

The 500 realizations, PSD power averaging, RMS calculations, autocorrelation averaging/normalization, Allan-variance averaging, tone metrics, and plot layout remain byte-for-byte the same outside that burn-in edit. The existing `AR` variable names and plot text remain as well; they refer to the ARMA output when these coefficients are loaded. MATLAB filters each column independently for this matrix input. [MathWorks: filter](https://www.mathworks.com/help/matlab/ref/filter.html)

**Execution and verification limits**

Use your existing data-loading expression in place of `YOUR_DATA`, choose the MATLAB and C++ directories, and run identification/export before validation. The C++ file remains part of your simulator: the original external functions, globals, bias handling, and incomplete frame-matrix placeholders require your existing project definitions. The supplied original sets only two matrix entries and contains `... existing matrix values ...`; it is not a standalone simulator. Use your complete matrix from the actual project. No test measurements or fitted coefficient CSVs were available for this task, so none were fabricated.

Advance the C++ stochastic filter once per sensor sample at the identified `Fs`. Its input must have zero mean and unit variance. Both histories persist across sample calls; reset both when starting a fresh independent simulation, using the same lifecycle as your existing AR state. The C++ state starts at zero as before, so exclude startup samples consistently when comparing with the MATLAB validation.

The C++ file passed a C++11 syntax check with declarations for its existing simulator interfaces. The actual loader and recurrence statements were then extracted unchanged and compared against `scipy.signal.lfilter` using identical inputs and initial states. Seven synthetic cases covered ARMA(10,4), MA order above AR order, pure MA, scalar-numerator AR, white noise, nonunit `A[0]`, and blank padding with Windows line endings. Each used 5,080 samples. The largest absolute difference was **5.56e-17**. Seven malformed/obsolete CSV cases were correctly rejected. A source comparison confirmed that validation has exactly the one advertised executable-line edit.

**MATLAB is unavailable in this environment.** The identification, MATLAB CSV writer, and 500-run validation were reviewed against the original source and MathWorks documentation but were not executed. The C++ numerical test validates coefficient loading and recursion, not a fit to your sensor or the full external simulator. ARMA estimation does not guarantee exact measured RMS or an improved autocorrelation; those remain outcomes to assess with your existing validation metrics.

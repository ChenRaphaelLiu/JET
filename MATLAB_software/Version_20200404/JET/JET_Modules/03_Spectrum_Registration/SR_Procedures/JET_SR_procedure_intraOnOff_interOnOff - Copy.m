function JET_STR = JET_SR_procedure_intraOnOff_interOnOff(JET_STR)
%JET_SR_procedure_intraOnOff_interOnOff The specific procedure that
%completes spectrum registration in the following manner:
%1) initial phase and frequency correction on the coil channel level
%2) register among On spectra
%3) register among Off spectra
%4) register On spectra to Off spectra
%
% Input arguments
% - JET_STR : The JET struct for the study.
%
% Output arguments
% - JET_STR : The modified JET struct for the study.
%
% Chen "Raphael" Liu (cl3760@columbia.edu) & Jia Guo (jg3400@columbia.edu),
% 02/24/2020.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%% OVERVIEW %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The overall goal is to perform spectrum registration on 3-D spectra.
% The spectra come with three dimensions:
% coil channel, repetition, and time/frequency. 
%
% The general plan is to keep two versions of the spectra data, Version 1
% with minimal pre-processing (to preserve as much raw signal as possible),
% and Version 2 with more pre-processing (to make the data smoother and
% easier to be registered). We will compute the transforms (frequency and
% phase deformations) using Version 2 and apply them on Version 1. In other
% words, Version 2 is a cleaner representation of Version 1.
%
% Specifically, we will carry out the procedure in the following steps.
% 1. Generate 3-D spectra Version 1 and Version 2 (already completed).
%    - Version 1: zero-filling, Fourier Transform.
%    - Version 2: zero-filling, denoising along time (resolution and
%                 enhancement), Fourier Transform.
% 2. Initial Phase (ACME) and Frequency (icoshift) correction to remove the
%    coil-dependent, repetition-independent phase and frequency
%    differences. We use the channel-separate repetition-combined mean
%    spectra from Version 2 to calculate the transforms.
% 3. Denoising across repetition. Moving-average with Gaussian weighting.
%    Again, this is only applied on Version 2 to make the spectra more
%    suitable for spectrum registration.
% 4. Iteratively carry out spectrum registration.
%    1) Compute moving-average weighted spectrum for each coil channel and
%       each repetition.
%    2) For each coil channel, register spectra across repetitions.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% How many repetitions per coil channel.
JET_STR.SR.params.num_repetition = JET_STR.SR.params.num_row / (JET_STR.SR.params.num_channel * 2);

% Reshape the matrices into the following shape:
% (coil channel) x (repetition) x (spectrum length).
spectrum_less_processing_reshape = ...
    reshape(JET_STR.SR.data.spectrum_less_processing, ...
    JET_STR.SR.params.ZeroFillTo, JET_STR.SR.params.num_channel, 2, JET_STR.SR.params.num_repetition);
spectrum_more_processing_reshape = ...
    reshape(JET_STR.SR.data.spectrum_more_processing, ...
    JET_STR.SR.params.ZeroFillTo, JET_STR.SR.params.num_channel, 2, JET_STR.SR.params.num_repetition);

on_all_less_processing_SepChannel_SepRep = ...
    squeeze(spectrum_less_processing_reshape(:, :, 1, :));
on_all_less_processing_SepChannel_SepRep = ...
    permute(on_all_less_processing_SepChannel_SepRep, [2, 3, 1]);
off_all_less_processing_SepChannel_SepRep = ...
    squeeze(spectrum_less_processing_reshape(:, :, 2, :));
off_all_less_processing_SepChannel_SepRep = ...
    permute(off_all_less_processing_SepChannel_SepRep, [2, 3, 1]);

on_all_more_processing_SepChannel_SepRep = ...
    squeeze(spectrum_more_processing_reshape(:, :, 1, :));
on_all_more_processing_SepChannel_SepRep = ...
    permute(on_all_more_processing_SepChannel_SepRep, [2, 3, 1]);
off_all_more_processing_SepChannel_SepRep = ...
    squeeze(spectrum_more_processing_reshape(:, :, 2, :));
off_all_more_processing_SepChannel_SepRep = ...
    permute(off_all_more_processing_SepChannel_SepRep, [2, 3, 1]);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Initial phase correction with ACME. Calculate the correction with
%%%% Version 2 and apply the transform on Version 1 and Version 2.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Calculate the phase correction.
on_spectra_phase_shift_by_coil_channel = ...
    JET_SR_calculate_phase_correction_ACME(on_all_more_processing_SepChannel_SepRep);
off_spectra_phase_shift_by_coil_channel = ...
    JET_SR_calculate_phase_correction_ACME(off_all_more_processing_SepChannel_SepRep);

% Apply the phase correction.
on_all_less_processing_SepChannel_SepRep_ACMEcorrected = ...
    JET_SR_apply_phase_correction_ACME(on_all_less_processing_SepChannel_SepRep, ...
    on_spectra_phase_shift_by_coil_channel);
off_all_less_processing_SepChannel_SepRep_ACMEcorrected = ...
    JET_SR_apply_phase_correction_ACME(off_all_less_processing_SepChannel_SepRep, ...
    off_spectra_phase_shift_by_coil_channel);
on_all_more_processing_SepChannel_SepRep_ACMEcorrected = ...
    JET_SR_apply_phase_correction_ACME(on_all_more_processing_SepChannel_SepRep, ...
    on_spectra_phase_shift_by_coil_channel);
off_all_more_processing_SepChannel_SepRep_ACMEcorrected = ...
    JET_SR_apply_phase_correction_ACME(off_all_more_processing_SepChannel_SepRep, ...
    off_spectra_phase_shift_by_coil_channel);

ACME_phase_shift = [on_spectra_phase_shift_by_coil_channel, off_spectra_phase_shift_by_coil_channel];

% PLOT: DEMONSTRATE THE EFFECT OF INITIAL PHASE CORRECTION.
% Demonstrate the effect of the initial ACME phase correction on the
% channel-separate repetition-combined data.
if JET_STR.SR.params.num_channel == 1
    on_all_less_processing_SepChannel_CombRep = ...
        squeeze(mean(on_all_less_processing_SepChannel_SepRep, 2))';
    off_all_less_processing_SepChannel_CombRep = ...
        squeeze(mean(off_all_less_processing_SepChannel_SepRep, 2))';
    on_all_more_processing_SepChannel_CombRep = ...
        squeeze(mean(on_all_more_processing_SepChannel_SepRep, 2))';
    off_all_more_processing_SepChannel_CombRep = ...
        squeeze(mean(off_all_more_processing_SepChannel_SepRep, 2))';
    on_all_more_processing_SepChannel_CombRep_ACMEcorrected = ...
        squeeze(mean(on_all_more_processing_SepChannel_SepRep_ACMEcorrected, 2))';
    off_all_more_processing_SepChannel_CombRep_ACMEcorrected = ...
        squeeze(mean(off_all_more_processing_SepChannel_SepRep_ACMEcorrected, 2))';
else
    on_all_less_processing_SepChannel_CombRep = ...
        squeeze(mean(on_all_less_processing_SepChannel_SepRep, 2));
    off_all_less_processing_SepChannel_CombRep = ...
        squeeze(mean(off_all_less_processing_SepChannel_SepRep, 2));
    on_all_more_processing_SepChannel_CombRep = ...
        squeeze(mean(on_all_more_processing_SepChannel_SepRep, 2));
    off_all_more_processing_SepChannel_CombRep = ...
        squeeze(mean(off_all_more_processing_SepChannel_SepRep, 2));
    on_all_more_processing_SepChannel_CombRep_ACMEcorrected = ...
        squeeze(mean(on_all_more_processing_SepChannel_SepRep_ACMEcorrected, 2));
    off_all_more_processing_SepChannel_CombRep_ACMEcorrected = ...
        squeeze(mean(off_all_more_processing_SepChannel_SepRep_ACMEcorrected, 2));
end

h14 = figure(14);
subplot(3, 2, 1)
plot(real(off_all_more_processing_SepChannel_CombRep)')
set(gca, 'Xdir', 'reverse')
legend('ch1', 'ch2', 'ch3', 'ch4', 'Location', 'southwest')
title('Raw Mean Off Spectra')
subplot(3, 2, 3)
plot(real(on_all_more_processing_SepChannel_CombRep)')
set(gca, 'Xdir', 'reverse')
legend('ch1', 'ch2', 'ch3', 'ch4', 'Location', 'southwest')
title('Raw Mean On Spectra')
subplot(3, 2, 5)
plot(real(on_all_more_processing_SepChannel_CombRep - off_all_more_processing_SepChannel_CombRep)')
set(gca, 'Xdir', 'reverse')
legend('ch1', 'ch2', 'ch3', 'ch4', 'Location', 'southwest')
title('Raw Mean Diff Spectra')
subplot(3, 2, 2)
plot(real(off_all_more_processing_SepChannel_CombRep_ACMEcorrected)')
set(gca, 'Xdir', 'reverse')
legend('ch1', 'ch2', 'ch3', 'ch4', 'Location', 'southwest')
title('Mean Off Spectra (Inter-channel Phase Correction)')
subplot(3, 2, 4)
plot(real(on_all_more_processing_SepChannel_CombRep_ACMEcorrected)')
set(gca, 'Xdir', 'reverse')
legend('ch1', 'ch2', 'ch3', 'ch4', 'Location', 'southwest')
title('Mean On Spectra (Inter-channel Phase Correction)')
subplot(3, 2, 6)
plot(real(on_all_more_processing_SepChannel_CombRep_ACMEcorrected - off_all_more_processing_SepChannel_CombRep_ACMEcorrected)')
set(gca, 'Xdir', 'reverse')
legend('ch1', 'ch2', 'ch3', 'ch4', 'Location', 'southwest')
title('Mean Diff Spectra (Inter-channel Phase Correction)')
if JET_STR.Report.save_intermediate_figures == 1 && JET_STR.SR.params.num_channel > 1
    saveas(h14, strcat(JET_STR.Report.report_dir, '/', JET_STR.Report.Subject_foldername, '_Report_initial_phase_correction.png'))
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Initial frequency correction with icoshift.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define the frequency bounds for ICOSHIFT.
icoshift_freqbounds1 = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.icoshift_upperbound1, JET_STR.SR.params.icoshift_lowerbound1);

icoshift_freqbounds2 = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.icoshift_upperbound2, JET_STR.SR.params.icoshift_lowerbound2);

icoshift_freqbounds = [icoshift_freqbounds2, icoshift_freqbounds1];

% Calculate the frequency correction.
on_spectra_frequency_shift_by_coil_channel = ...
    JET_SR_calculate_frequency_correction_ICOSHIFT(on_all_more_processing_SepChannel_SepRep_ACMEcorrected, icoshift_freqbounds);
off_spectra_frequency_shift_by_coil_channel = ...
    JET_SR_calculate_frequency_correction_ICOSHIFT(off_all_more_processing_SepChannel_SepRep_ACMEcorrected, icoshift_freqbounds);

% Apply the frequency correction.
on_all_less_processing_SepChannel_SepRep_ICOcorrected = ...
    JET_SR_apply_frequency_correction_ICOSHIFT(on_all_less_processing_SepChannel_SepRep_ACMEcorrected, ...
    on_spectra_frequency_shift_by_coil_channel);
off_all_less_processing_SepChannel_SepRep_ICOcorrected = ...
    JET_SR_apply_frequency_correction_ICOSHIFT(off_all_less_processing_SepChannel_SepRep_ACMEcorrected, ...
    off_spectra_frequency_shift_by_coil_channel);
on_all_more_processing_SepChannel_SepRep_ICOcorrected = ...
    JET_SR_apply_frequency_correction_ICOSHIFT(on_all_more_processing_SepChannel_SepRep_ACMEcorrected, ...
    on_spectra_frequency_shift_by_coil_channel);
off_all_more_processing_SepChannel_SepRep_ICOcorrected = ...
    JET_SR_apply_frequency_correction_ICOSHIFT(off_all_more_processing_SepChannel_SepRep_ACMEcorrected, ...
    off_spectra_frequency_shift_by_coil_channel);

icoshift_frequency_shift = [on_spectra_frequency_shift_by_coil_channel, off_spectra_frequency_shift_by_coil_channel];

% Duplicate/back up the data before our spectrum registration.
JET_STR.SR.data.on_all_less_processing_SepChannel_SepRep_beforeSR = ...
    on_all_less_processing_SepChannel_SepRep_ICOcorrected;
JET_STR.SR.data.off_all_less_processing_SepChannel_SepRep_beforeSR = ...
    off_all_less_processing_SepChannel_SepRep_ICOcorrected;
JET_STR.SR.data.on_all_more_processing_SepChannel_SepRep_beforeSR = ...
    on_all_more_processing_SepChannel_SepRep_ICOcorrected;
JET_STR.SR.data.off_all_more_processing_SepChannel_SepRep_beforeSR = ...
    off_all_more_processing_SepChannel_SepRep_ICOcorrected;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Store the frequency and phase drifts for future report.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
sw_ppm = range(JET_STR.SR.data.frequency_axis);
resolution_ppm = sw_ppm ./ (length(JET_STR.SR.data.frequency_axis) - 1);
resolution_Hz = resolution_ppm * 42.6 * JET_STR.SR.params.field_strength;

JET_STR.SR.data.ACME_drift_rad = ACME_phase_shift .* pi ./ 180;
JET_STR.SR.data.icoshift_drift_Hz = icoshift_frequency_shift .* resolution_Hz;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% We assume that by now we have corrected for most of the coil
%%%% channel-dependent frequency and phase difference. Therefore we can
%%%% combine the coil channels now.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_all_less_processing_CombChannel_SepRep_SR_input = ...
    squeeze(mean(on_all_less_processing_SepChannel_SepRep_ICOcorrected, 1));
off_all_less_processing_CombChannel_SepRep_SR_input = ...
    squeeze(mean(off_all_less_processing_SepChannel_SepRep_ICOcorrected, 1));
on_all_more_processing_CombChannel_SepRep_SR_input = ...
    squeeze(mean(on_all_more_processing_SepChannel_SepRep_ICOcorrected, 1));
off_all_more_processing_CombChannel_SepRep_SR_input = ...
    squeeze(mean(off_all_more_processing_SepChannel_SepRep_ICOcorrected, 1));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Inter-repetition smoothing.
%%%% We will use the smoothed version to calculate the spectrum
%%%% registration tranforms, and apply the transforms on the original data.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
gaussian_window = gausswin(...
    size(on_all_more_processing_CombChannel_SepRep_SR_input, 1), ...
    JET_STR.SR.params.SR_RepSmooth_Alpha);
gaussian_window_normalized = gaussian_window ./ sum(gaussian_window);
gaussian_filter = @(signal) conv(signal, gaussian_window_normalized, 'same');

on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth = ...
    zeros(size(on_all_more_processing_CombChannel_SepRep_SR_input));
off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth = ...
    zeros(size(off_all_more_processing_CombChannel_SepRep_SR_input));
for frequency_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_input, 2)
    on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth(:, frequency_index) = ...
        gaussian_filter(on_all_more_processing_CombChannel_SepRep_SR_input(:, frequency_index));
    off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth(:, frequency_index) = ...
        gaussian_filter(off_all_more_processing_CombChannel_SepRep_SR_input(:, frequency_index));
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Spectrum Registration Part 1.
%%%% 1. Register ON spectra together.
%%%% 2. Register OFF spectra together.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% How do we optimize the parameters for spectrum registration?
% We define the pair [chemical_shift, zero_order_phase], and optimize the 
% resulting spectrum. That is to say, we need to find the FID from the 
% initial moving spectrum first, and then apply the 
% [chemical_shift, zero_order_phase] pair onto the FID and find the
% parameters that will yield a resulting spectrum that best resembles the
% template spectrum.

if JET_STR.SR.perform_SR_or_not == 1
    SR_freqbounds = ...
        JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis, ...
        JET_STR.SR.params.SR_upperbound, JET_STR.SR.params.SR_lowerbound);

    %%%% COMPONENT 0. Initializations. %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % 1. Initialize matrices to store the registration parameters
    % [chemical_shift, zero_order_phase].
    on_all_repetitions_SR_params = ...
        zeros(size(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 1), 2);
    off_all_repetitions_SR_params = ...
        zeros(size(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 1), 2);
    % 2. Initialize the updated spectra.
    on_all_more_processing_CombChannel_SepRep_SR_updated = ...
        zeros(size(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth));
    off_all_more_processing_CombChannel_SepRep_SR_updated = ...
        zeros(size(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth));
    % 3. Initialize similarity matrices. to represent the
    % similarity between each individual spectrum and the template.
    on_all_more_processing_SR_RepSmooth_similarity = ...
        zeros(size(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 1), 1);
    off_all_more_processing_SR_RepSmooth_similarity = ...
        zeros(size(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 1), 1);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    for SR_iteration_index = 1 : JET_STR.SR.params.SR_iterations
        %%%%% COMPONENT 1. Prepare the spectrum templates. %%%%%%%%%%%%%%%%
        % For the first iteration, use the mean spectrum as the template.
        if SR_iteration_index == 1
            if strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'real')
                on_all_more_processing_SR_template = ...
                    mean(real(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth), 1);
                off_all_more_processing_SR_template = ...
                    mean(real(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth), 1);
            elseif strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'complex')
                on_all_more_processing_SR_template = ...
                    mean(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 1);
                off_all_more_processing_SR_template = ...
                    mean(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 1);
            end
        % For subsequent iterations, use the weighted sum of each
        % individual spectrum (with the weights proportional to the 
        % similarity between each individual spectrum and the current 
        % template) as the new template.
        else
            on_all_more_processing_SR_weightings = ...
                repmat(on_all_more_processing_SR_RepSmooth_similarity_normalized , ...
                [1, size(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 2)]);
            off_all_more_processing_SR_weightings = ...
                repmat(off_all_more_processing_SR_RepSmooth_similarity_normalized , ...
                [1, size(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 2)]);

            if strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'real')
                on_all_more_processing_SR_template = ...
                    sum(real(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth) .* ...
                    on_all_more_processing_SR_weightings, 1);
                off_all_more_processing_SR_template = ...
                    sum(real(off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth) .* ...
                    off_all_more_processing_SR_weightings, 1);
            elseif strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'complex')
                on_all_more_processing_SR_template = ...
                    sum(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth .* ...
                    on_all_more_processing_SR_weightings, 1);
                off_all_more_processing_SR_template = ...
                    sum(off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth .* ...
                    off_all_more_processing_SR_weightings, 1);
            end
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        %%%%% COMPONENT 2. Register each spectrum to the spectrum template.
        % This process abides by the general philosophy of spectrum
        % registration, that is to say, we use the inter-repetition
        % smoothed version 
        % (*_singleRep_RepSmooth_more_processing_moving_FID)
        % to calculate the transform needed, and apply these calculated
        % transform on the version without smoothing
        % (*_singleRep_more_processing_moving_FID).
        % Later on, when the entire SR is done, we will apply the final
        % version of the transform on the version without smoothing and
        % without much pre-processing
        % (*_singleRep_less_processing_moving_FID) for better downstream
        % quantification.
        %
        % Initialize spectral deformation parameters.
        % [chemical_shift, zero_order_phase]
        SR_params_initial = [0, 0];
        for repetition_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 1)
            % Reverse-calculate the moving FID from the initial moving spectrum.
            on_singleRep_more_processing_moving_FID = ...
                ifft(fliplr(on_all_more_processing_CombChannel_SepRep_SR_input(repetition_index, :)));
            off_singleRep_more_processing_moving_FID = ...
                ifft(fliplr(off_all_more_processing_CombChannel_SepRep_SR_input(repetition_index, :)));
            on_singleRep_RepSmooth_more_processing_moving_FID = ...
                ifft(fliplr(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth(repetition_index, :)));
            off_singleRep_RepSmooth_more_processing_moving_FID = ...
                ifft(fliplr(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth(repetition_index, :)));

            if strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'real')
                % Spectrum Registration, within On spectra.
                [on_singleRep_SR_params] = lsqcurvefit(@(parameters, SR_params_initial) ...
                    JET_helper_function_spectrum_deformation_real(parameters, ...
                    SR_params_initial, SR_freqbounds, on_singleRep_RepSmooth_more_processing_moving_FID, ...
                    JET_STR.SR.params.LS_mode), SR_params_initial, JET_STR.SR.data.time_zeropad, ...
                    real(on_all_more_processing_SR_template(SR_freqbounds)));
                % Spectrum Registration, within Off spectra.
                [off_singleRep_SR_params] = lsqcurvefit(@(parameters, SR_params_initial) ...
                    JET_helper_function_spectrum_deformation_real(parameters, ...
                    SR_params_initial, SR_freqbounds, off_singleRep_RepSmooth_more_processing_moving_FID, ...
                    JET_STR.SR.params.LS_mode), SR_params_initial, JET_STR.SR.data.time_zeropad, ...
                    real(off_all_more_processing_SR_template(SR_freqbounds)));
            elseif strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'complex')
                % Spectrum Registration, within On spectra.
                [on_singleRep_SR_params] = lsqcurvefit(@(parameters, SR_params_initial) ...
                    JET_helper_function_spectrum_deformation_complex(parameters, ...
                    SR_params_initial, SR_freqbounds, on_singleRep_RepSmooth_more_processing_moving_FID, ...
                    JET_STR.SR.params.LS_mode), SR_params_initial, JET_STR.SR.data.time_zeropad, ...
                    on_all_more_processing_SR_template(SR_freqbounds));
                % Spectrum Registration, within Off spectra.
                [off_singleRep_SR_params] = lsqcurvefit(@(parameters, SR_params_initial) ...
                    JET_helper_function_spectrum_deformation_complex(parameters, ...
                    SR_params_initial, SR_freqbounds, off_singleRep_RepSmooth_more_processing_moving_FID, ...
                    JET_STR.SR.params.LS_mode), SR_params_initial, JET_STR.SR.data.time_zeropad, ...
                    off_all_more_processing_SR_template(SR_freqbounds));
            end

            % Update the spectrum registration parameters for the current repetition.
            on_all_repetitions_SR_params(repetition_index, :) = ...
                on_singleRep_SR_params + on_all_repetitions_SR_params(repetition_index, :);
            off_all_repetitions_SR_params(repetition_index, :) = ...
                off_singleRep_SR_params + off_all_repetitions_SR_params(repetition_index, :);

            % Calculate the new spectrum after this current iteration of
            % spectrum registration. Remember to use the version without
            % inter-repetition smoothing.
            on_all_more_processing_CombChannel_SepRep_SR_updated(repetition_index, :) = ...
                JET_helper_function_spectrum_deformation_complex(on_all_repetitions_SR_params(repetition_index, :), ...
                JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
                on_singleRep_more_processing_moving_FID, JET_STR.SR.params.LS_mode);
            off_all_more_processing_CombChannel_SepRep_SR_updated(repetition_index, :) = ...
                JET_helper_function_spectrum_deformation_complex(off_all_repetitions_SR_params(repetition_index, :), ...
                JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
                off_singleRep_more_processing_moving_FID, JET_STR.SR.params.LS_mode);
        end

        % Apply inter-repetition smoothing on the newly registered spectra.
        on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth = ...
            zeros(size(on_all_more_processing_CombChannel_SepRep_SR_updated));
        off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth = ...
            zeros(size(off_all_more_processing_CombChannel_SepRep_SR_updated));
        for frequency_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_updated, 2)
            on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth(:, frequency_index) = ...
                gaussian_filter(on_all_more_processing_CombChannel_SepRep_SR_updated(:, frequency_index));
            off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth(:, frequency_index) = ...
                gaussian_filter(off_all_more_processing_CombChannel_SepRep_SR_updated(:, frequency_index));
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        %%%%% COMPONENT 3. Calculate and normalize similarity %%%%%%%%%%%%%
        % Similarity is defined between each individual spectrum and the 
        % current template.
        if strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'real')
            for repetition_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth, 1)
                correlation_coefficient_matrix = ...
                    corrcoef([real(on_all_more_processing_SR_template(SR_freqbounds))', ...
                    real(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth(repetition_index, SR_freqbounds))']);
                on_all_more_processing_SR_RepSmooth_similarity(repetition_index, :) = ...
                    correlation_coefficient_matrix(1, 2);
                correlation_coefficient_matrix = ...
                    corrcoef([real(off_all_more_processing_SR_template(SR_freqbounds))', ...
                    real(off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth(repetition_index, SR_freqbounds))']);
                off_all_more_processing_SR_RepSmooth_similarity(repetition_index, :) = ...
                    correlation_coefficient_matrix(1, 2);
            end
        elseif strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'complex')
            for repetition_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth, 1)
                correlation_coefficient_matrix = ...
                    corrcoef([on_all_more_processing_SR_template(SR_freqbounds)', ...
                    on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth(repetition_index, SR_freqbounds)']);
                on_all_more_processing_SR_RepSmooth_similarity(repetition_index, :) = ...
                    abs(correlation_coefficient_matrix(1, 2));
                correlation_coefficient_matrix = ...
                    corrcoef([off_all_more_processing_SR_template(SR_freqbounds)', ...
                    off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth(repetition_index, SR_freqbounds)']);
                off_all_more_processing_SR_RepSmooth_similarity(repetition_index, :) = ...
                    abs(correlation_coefficient_matrix(1, 2));
            end
        end

        % Normalize the similarity matrices such that the sum is 1. This is
        % necessary for creating a new spectrum template as the weighted
        % sum of all spectra.
        on_all_more_processing_SR_RepSmooth_similarity_normalized = ...
            on_all_more_processing_SR_RepSmooth_similarity ./ ...
            sum(on_all_more_processing_SR_RepSmooth_similarity);
        off_all_more_processing_SR_RepSmooth_similarity_normalized = ...
            off_all_more_processing_SR_RepSmooth_similarity ./ ...
            sum(off_all_more_processing_SR_RepSmooth_similarity);
        
        % If this is the last iteration, we will update the templates for
        % the On/Off spectra once again. Also we will save the similarity
        % matrices.
        if SR_iteration_index == JET_STR.SR.params.SR_iterations
            on_all_more_processing_SR_weightings = ...
                repmat(on_all_more_processing_SR_RepSmooth_similarity_normalized , ...
                [1, size(on_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 2)]);
            off_all_more_processing_SR_weightings = ...
                repmat(off_all_more_processing_SR_RepSmooth_similarity_normalized , ...
                [1, size(off_all_more_processing_CombChannel_SepRep_SR_input_RepSmooth, 2)]);

            if strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'real')
                on_all_more_processing_SR_template = ...
                    sum(real(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth) .* ...
                    on_all_more_processing_SR_weightings, 1);
                off_all_more_processing_SR_template = ...
                    sum(real(off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth) .* ...
                    off_all_more_processing_SR_weightings, 1);
            elseif strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'complex')
                on_all_more_processing_SR_template = ...
                    sum(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth .* ...
                    on_all_more_processing_SR_weightings, 1);
                off_all_more_processing_SR_template = ...
                    sum(off_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth .* ...
                    off_all_more_processing_SR_weightings, 1);
            end
            
            JET_STR.SR.data.on_all_more_processing_SR_RepSmooth_similarity = ...
                on_all_more_processing_SR_RepSmooth_similarity;
            JET_STR.SR.data.off_all_more_processing_SR_RepSmooth_similarity = ...
                off_all_more_processing_SR_RepSmooth_similarity;
        end
    end
else
    % I will leave this empty for now.
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Important step: Outlier detection.
%%% We will use the similarity matrices along with the registration
%%% parameters to determine which repetitions are "good" and which
%%% repetitions are "bad outliers". We will store the "isOutlier" matrix
%%% for the following steps, and the user can decide whether or not to
%%% exclude the outliers from the Spectral Fitting step.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
feature_matrix_for_outlier_detection = ...
    [JET_STR.SR.data.on_all_more_processing_SR_RepSmooth_similarity, ...
    JET_STR.SR.data.on_all_more_processing_SR_RepSmooth_similarity, ...
    on_all_repetitions_SR_params, ...
    off_all_repetitions_SR_params];

JET_STR.SR.data.outlier_array = sum(isoutlier(feature_matrix_for_outlier_detection, 'mean'), 2);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Spectrum Registration Part 1 is complete.
%%% Now we have registered:
%%% 1. Among individual On spectra.
%%% 2. Among individual Off spectra.
%%% We now need to record the registered spectra and parameters to JET_STR.
%%% Remember that we also need to keep the version where not only
%%% inter-repetition smoothing was not performed, but also as little
%%% pre-processing as possible was done.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
JET_STR.SR.data.on_all_repetitions_SR_params = on_all_repetitions_SR_params;
JET_STR.SR.data.off_all_repetitions_SR_params = off_all_repetitions_SR_params;

JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff = ...
    zeros(size(on_all_less_processing_CombChannel_SepRep_SR_input));
JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff = ...
    zeros(size(off_all_less_processing_CombChannel_SepRep_SR_input));
JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff = ...
    zeros(size(on_all_more_processing_CombChannel_SepRep_SR_input));
JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff = ...
    zeros(size(off_all_more_processing_CombChannel_SepRep_SR_input));

for repetition_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth, 1)
    % Reverse-calculate the moving FID from the initial moving spectrum.
    on_singleRep_less_processing_moving_FID = ...
        ifft(fliplr(on_all_less_processing_CombChannel_SepRep_SR_input(repetition_index, :)));
    off_singleRep_less_processing_moving_FID = ...
        ifft(fliplr(off_all_less_processing_CombChannel_SepRep_SR_input(repetition_index, :)));
    on_singleRep_more_processing_moving_FID = ...
        ifft(fliplr(on_all_more_processing_CombChannel_SepRep_SR_input(repetition_index, :)));
    off_singleRep_more_processing_moving_FID = ...
        ifft(fliplr(off_all_more_processing_CombChannel_SepRep_SR_input(repetition_index, :)));

    JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff(repetition_index, :) = ...
        JET_helper_function_spectrum_deformation_complex(on_all_repetitions_SR_params(repetition_index, :), ...
        JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
        on_singleRep_less_processing_moving_FID, JET_STR.SR.params.LS_mode);
    JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff(repetition_index, :) = ...
        JET_helper_function_spectrum_deformation_complex(off_all_repetitions_SR_params(repetition_index, :), ...
        JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
        off_singleRep_less_processing_moving_FID, JET_STR.SR.params.LS_mode);
    JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff(repetition_index, :) = ...
        JET_helper_function_spectrum_deformation_complex(on_all_repetitions_SR_params(repetition_index, :), ...
        JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
        on_singleRep_more_processing_moving_FID, JET_STR.SR.params.LS_mode);
    JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff(repetition_index, :) = ...
        JET_helper_function_spectrum_deformation_complex(off_all_repetitions_SR_params(repetition_index, :), ...
        JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
        off_singleRep_more_processing_moving_FID, JET_STR.SR.params.LS_mode);
end

JET_STR.SR.data.on_all_repetitions_SR_params = on_all_repetitions_SR_params;
JET_STR.SR.data.off_all_repetitions_SR_params = off_all_repetitions_SR_params;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Spectrum Registration Part 2.
%%%% 3. Register ON spectra onto OFF spectra.
% Specifically, we would assume that each individual spectrum within ON or
% OFF is correctly registered. Therefore, we would only need to find the
% tranform to register the ON template spectrum onto the OFF template
% spectrum, and apply that same transform to each individual ON spectrum.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Define the frequency bound for On-to-Off registration.
SRfreqbounds_On_to_Off_1 = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.SRfreq_upperbound_On_to_Off_1, JET_STR.SR.params.SRfreq_lowerbound_On_to_Off_1);

SRfreqbounds_On_to_Off_2 = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.SRfreq_upperbound_On_to_Off_2, JET_STR.SR.params.SRfreq_lowerbound_On_to_Off_2);

SRfreqbounds_On_to_Off_3 = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.SRfreq_upperbound_On_to_Off_3, JET_STR.SR.params.SRfreq_lowerbound_On_to_Off_3);

SRfreqbounds_On_to_Off = [SRfreqbounds_On_to_Off_1, SRfreqbounds_On_to_Off_2, SRfreqbounds_On_to_Off_3];

% Reverse-calculate the FIDs for the On template.
on_all_more_processing_template_FID = ifft(fliplr(on_all_more_processing_SR_template));

if strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'real')
    % Spectrum Registration, On template to Off template.
    [on_to_off_template_SR_params] = lsqcurvefit(@(parameters, SR_params_initial) ...
        JET_helper_function_spectrum_deformation_real(parameters, ...
        SR_params_initial, SRfreqbounds_On_to_Off, on_all_more_processing_template_FID, ...
        JET_STR.SR.params.LS_mode), SR_params_initial, JET_STR.SR.data.time_zeropad, ...
        real(off_all_more_processing_SR_template(SRfreqbounds_On_to_Off)));
elseif strcmp(JET_STR.SR.params.SR_with_real_or_complex, 'complex')
    % Spectrum Registration, On template to Off template.
    [on_to_off_template_SR_params] = lsqcurvefit(@(parameters, SR_params_initial) ...
        JET_helper_function_spectrum_deformation_complex(parameters, ...
        SR_params_initial, SRfreqbounds_On_to_Off, on_all_more_processing_template_FID, ...
        JET_STR.SR.params.LS_mode), SR_params_initial, JET_STR.SR.data.time_zeropad, ...
        off_all_more_processing_SR_template(SRfreqbounds_On_to_Off));
end

%%%% Calculate the new On spectrum after this On-to-Off spectrum registration.
% Note that we only need the update the On spectra, since the Off spectra
% are regarded as the registration target.
%
% On template spectrum.
JET_STR.SR.data.on_all_more_processing_SR_template_OnOffReg = ...
    JET_helper_function_spectrum_deformation_complex(on_to_off_template_SR_params, ...
    JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
    on_all_more_processing_template_FID, JET_STR.SR.params.LS_mode);

% Each individual repetition in the On spectra.
for repetition_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth, 1)
    % Reverse-calculate the moving FID from the initial moving spectrum.
    on_singleRep_less_processing_moving_FID = ...
        ifft(fliplr(on_all_less_processing_CombChannel_SepRep_SR_input(repetition_index, :)));
    on_singleRep_more_processing_moving_FID = ...
        ifft(fliplr(on_all_more_processing_CombChannel_SepRep_SR_input(repetition_index, :)));
    % Apply the transform on each repetition of On spectra.
    JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_OnOffReg(repetition_index, :) = ...
        JET_helper_function_spectrum_deformation_complex(on_all_repetitions_SR_params(repetition_index, :) + on_to_off_template_SR_params, ...
        JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
        on_singleRep_less_processing_moving_FID, JET_STR.SR.params.LS_mode);
    JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_OnOffReg(repetition_index, :) = ...
        JET_helper_function_spectrum_deformation_complex(off_all_repetitions_SR_params(repetition_index, :) + on_to_off_template_SR_params, ...
        JET_STR.SR.data.time_zeropad, 1 : length(JET_STR.SR.data.frequency_axis), ...
        on_singleRep_more_processing_moving_FID, JET_STR.SR.params.LS_mode);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Spectrum Registration Part 2 is Complete.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Spectrum Registration Part 3.
%%%% 3. Shift the spectra globally based on priors.
% We use the prior such that NAA shall be at 2 ppm to shift the spectra
% accordingly.
% How do we do that? We use the Off template to find the reasonable amount
% of shifting and apply that to all the spectra we have.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
NAA_freqbounds = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.NAA_target_upperbound, JET_STR.SR.params.NAA_target_lowerbound);

off_all_more_processing_template_NAAregion = off_all_more_processing_SR_template(NAA_freqbounds);

[~, NAA_target_region_max_index] = max(off_all_more_processing_template_NAAregion);
frequency_shift_to_adjust_NAA_to_2ppm = round(NAA_target_region_max_index - length(NAA_freqbounds) / 2);

% Initialize matrices to store the final corrected spectra.
JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_final = ...
    zeros(size(JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_OnOffReg));
JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final = ...
    zeros(size(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_OnOffReg));
JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_final = ...
    zeros(size(JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff));
JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final = ...
    zeros(size(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff));

for repetition_index = 1 : size(on_all_more_processing_CombChannel_SepRep_SR_updated_RepSmooth, 1)
    JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_final(repetition_index, :) = ...
        my_shift(JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_OnOffReg(repetition_index, :), ...
        frequency_shift_to_adjust_NAA_to_2ppm);
    JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final(repetition_index, :) = ...
        my_shift(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_OnOffReg(repetition_index, :), ...
        frequency_shift_to_adjust_NAA_to_2ppm);
    JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_final(repetition_index, :) = ...
        my_shift(JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff(repetition_index, :), ...
        frequency_shift_to_adjust_NAA_to_2ppm);
    JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final(repetition_index, :) = ...
        my_shift(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff(repetition_index, :), ...
        frequency_shift_to_adjust_NAA_to_2ppm);
end

JET_STR.SR.data.diff_all_more_processing_CombChannel_SepRep_SR_final = ...
    JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final - ...
    JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final;

% Also save the inter-repetition gaussian smoothed versions.
JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth = ...
    zeros(size(JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_final));
JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth = ...
    zeros(size(JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_final));
for frequency_index = 1 : size(JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_final, 2)
    JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, frequency_index) = ...
        gaussian_filter(JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_final(:, frequency_index));
    JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, frequency_index) = ...
        gaussian_filter(JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_final(:, frequency_index));
end
JET_STR.SR.data.diff_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth = ...
    JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth - ...
    JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth;

% We also want to store the template spectra after the final correction.
JET_STR.SR.data.on_all_more_processing_template_SR_final = ...
    my_shift(on_all_more_processing_SR_template, frequency_shift_to_adjust_NAA_to_2ppm);
JET_STR.SR.data.off_all_more_processing_template_SR_final = ...
    my_shift(off_all_more_processing_SR_template, frequency_shift_to_adjust_NAA_to_2ppm);

% Lastly, we want to save the mean spectra for On and Off.
JET_STR.SR.data.on_all_less_processing_mean_SR_final = ...
    mean(JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_final, 1);
JET_STR.SR.data.on_all_more_processing_mean_SR_final = ...
    mean(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final, 1);
JET_STR.SR.data.off_all_less_processing_mean_SR_final = ...
    mean(JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_final, 1);
JET_STR.SR.data.off_all_more_processing_mean_SR_final = ...
    mean(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final, 1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Spectrum Registration Part 3 is complete.
%%%% Spectrum Registration Complete!
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% Prepare statistics and data for the Report.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_all_more_processing_corrected_mean_real = real(JET_STR.SR.data.on_all_more_processing_mean_SR_final);
off_all_more_processing_corrected_mean_real = real(JET_STR.SR.data.off_all_more_processing_mean_SR_final);
diff_all_more_processing_corrected_mean_real = on_all_more_processing_corrected_mean_real - off_all_more_processing_corrected_mean_real;

% These three variables are saved for spectral fitting. Therefore we would
% like to use the less processed (more "authentic") data.
JET_STR.SR.data.on_average_SR = JET_STR.SR.data.on_all_less_processing_mean_SR_final;
JET_STR.SR.data.off_average_SR = JET_STR.SR.data.off_all_less_processing_mean_SR_final;
JET_STR.SR.data.diff_average_SR = JET_STR.SR.data.on_all_less_processing_mean_SR_final - JET_STR.SR.data.off_all_less_processing_mean_SR_final;

GABA_freqbounds = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.GABA_upperbound, JET_STR.SR.params.GABA_lowerbound);

Glx_freqbounds = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.Glx_upperbound, JET_STR.SR.params.Glx_lowerbound);

NAA_freqbounds = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.NAA_upperbound, JET_STR.SR.params.NAA_lowerbound);

ChoCr_freqbounds = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.ChoCr_upperbound, JET_STR.SR.params.ChoCr_lowerbound);

Noise_freqbounds = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.Noise_upperbound, JET_STR.SR.params.Noise_lowerbound);

GABA_S_power = sum((diff_all_more_processing_corrected_mean_real(GABA_freqbounds) - ...
    mean(diff_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);
GABA_N_power = sum((diff_all_more_processing_corrected_mean_real(Noise_freqbounds) - ...
    mean(diff_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);

Glx_S_power = sum((diff_all_more_processing_corrected_mean_real(Glx_freqbounds) - ...
    mean(diff_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);
Glx_N_power = sum((diff_all_more_processing_corrected_mean_real(Noise_freqbounds) - ...
    mean(diff_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);

NAA_S_power = sum((off_all_more_processing_corrected_mean_real(NAA_freqbounds) - ...
    mean(off_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);
NAA_N_power = sum((off_all_more_processing_corrected_mean_real(Noise_freqbounds) - ...
    mean(off_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);

ChoCr_S_power = sum((off_all_more_processing_corrected_mean_real(ChoCr_freqbounds) - mean(off_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);
ChoCr_N_power = sum((off_all_more_processing_corrected_mean_real(Noise_freqbounds) - mean(off_all_more_processing_corrected_mean_real(Noise_freqbounds))).^2);

GABA_SNR_DB = log(GABA_S_power / GABA_N_power); % DiffSpecData_corrected_average_real
Glx_SNR_DB = log(Glx_S_power / Glx_N_power); % DiffSpecData_corrected_average_real
NAA_SNR_DB = log(NAA_S_power / NAA_N_power); % OffSpecData_corrected_average_real
ChoCr_SNR_DB = log(ChoCr_S_power / ChoCr_N_power); % OffSpecData_corrected_average_real

JET_STR.Report.SNR.ChoCr_SNR_DB = ChoCr_SNR_DB;
JET_STR.Report.SNR.NAA_SNR_DB = NAA_SNR_DB;
JET_STR.Report.SNR.Glx_SNR_DB = Glx_SNR_DB;
JET_STR.Report.SNR.GABA_SNR_DB = GABA_SNR_DB;

%%%% Compute SNR.
Spectra_freqbounds = ...
    JET_helper_function_find_freqbounds(JET_STR.SR.data.frequency_axis,...
    JET_STR.SR.params.Spectra_upperbound, JET_STR.SR.params.Spectra_lowerbound);

%%% For now we will use the inter-repetition gaussian smoothed version.
on_all_more_processing_signal_power = sum((real(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Spectra_freqbounds)) - ...
    mean(real(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Noise_freqbounds)), 2)).^2, 2);
on_all_more_processing_noise_power = sum((real(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Noise_freqbounds)) - ...
    mean(real(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Noise_freqbounds)), 2)).^2, 2);

off_all_more_processing_signal_power = sum((real(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Spectra_freqbounds)) - ...
    mean(real(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Noise_freqbounds)), 2)).^2, 2);
off_all_more_processing_noise_power = sum((real(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Noise_freqbounds)) - ...
    mean(real(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_final_RepSmooth(:, Noise_freqbounds)), 2)).^2, 2);

JET_STR.Report.SNR.OnSpectra_SNR_DB = log(on_all_more_processing_signal_power ./ on_all_more_processing_noise_power);% OffSpecData_corrected_average_real
JET_STR.Report.SNR.OffSpectra_SNR_DB = log(off_all_more_processing_signal_power ./ off_all_more_processing_noise_power);% OffSpecData_corrected_average_real

% The following figure demonstrates the performance of Spectrum
% Registration. Only Version 2 (more processing) is shown.
% Left: Mean On spectrum and Mean Off spectrum overlayed.
% Right: Mean Diff spectrum.
% 1st row: Before channel combination, ACME, Icoshift.
% 2nd row: After channel combination, ACME, Icoshift, before SR.
% 3rd row: After On SR and Off SR.
% 4th row: After On-to-Off SR.
h3 = figure(3);
set(gcf, 'units', 'normalized', 'outerposition', [0, 0, 0.25, 0.5]);
subplot(4, 2, 1)
    plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
        real(mean(on_all_more_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(off_all_more_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds), 1)));
title('Mean On spectrum and Mean Off spectrum');
ylabel('Before initial correction');
subplot(4, 2, 2)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(on_all_more_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds) - ...
    off_all_more_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
title('Mean Diff spectrum');
subplot(4, 2, 3)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(on_all_more_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(off_all_more_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
ylabel('After initial correction');
subplot(4, 2, 4)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(on_all_more_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds) - ...
    off_all_more_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
subplot(4, 2, 5)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds), 1)));
ylabel('After On/Off SR');
subplot(4, 2, 6)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds) - ...
    JET_STR.SR.data.off_all_more_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
subplot(4, 2, 7)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_more_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.off_all_more_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds), 1)));
ylabel('After On-to-Off SR and NAA shifting');
subplot(4, 2, 8)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_more_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds) - ...
    JET_STR.SR.data.off_all_more_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');

if JET_STR.Report.save_intermediate_figures == 1
    pause(2);
    saveas(h3, strcat(JET_STR.Report.report_dir, '/', JET_STR.Report.Subject_foldername, '_SR_step-by-step_more_processing.png'));
end

% The same thing with Version 1 (less processing).
h4 = figure(4);
set(gcf, 'units', 'normalized', 'outerposition', [0, 0, 0.25, 0.5]);
subplot(4, 2, 1)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(on_all_less_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(off_all_less_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds), 1)));
title('Mean On spectrum and Mean Off spectrum');
ylabel('Before initial correction');
subplot(4, 2, 2)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(on_all_less_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds) - ...
    off_all_less_processing_SepChannel_CombRep(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
title('Mean Diff spectrum');
subplot(4, 2, 3)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(on_all_less_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(off_all_less_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds), 1)));
ylabel('After initial correction');
subplot(4, 2, 4)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(on_all_less_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds) - ...
    off_all_less_processing_CombChannel_SepRep_SR_input(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
subplot(4, 2, 5)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds), 1)));
ylabel('After On/Off SR');
subplot(4, 2, 6)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds) - ...
    JET_STR.SR.data.off_all_less_processing_CombChannel_SepRep_SR_WithinOnOrOff(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
subplot(4, 2, 7)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_less_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');
hold on;
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.off_all_less_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds), 1)));
ylabel('After On-to-Off SR and NAA shifting');
subplot(4, 2, 8)
plot(JET_STR.SR.data.frequency_axis(JET_STR.SR.data.Display_freqbounds), ...
    real(mean(JET_STR.SR.data.on_all_less_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds) - ...
    JET_STR.SR.data.off_all_less_processing_mean_SR_final(:, JET_STR.SR.data.Display_freqbounds), 1)));
set(gca, 'Xdir', 'reverse');

if JET_STR.Report.save_intermediate_figures == 1
    pause(2);
    saveas(h4, strcat(JET_STR.Report.report_dir, '/', JET_STR.Report.Subject_foldername, '_SR_step-by-step_less_processing.png'));
end

disp('... Spectrum Registration Complete.')

end
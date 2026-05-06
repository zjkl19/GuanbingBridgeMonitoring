classdef test_analyzer_pilot < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'analysis'));
        end
    end

    methods (Test)
        function deflectionAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'deflection_stats.xlsx');
            a = bms.analyzer.DeflectionAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'features_rs', struct());
            tc.verifyClass(a, 'bms.analyzer.DeflectionAnalyzer');
            tc.verifyEqual(a.Root, 'D:/data');
            tc.verifyEqual(a.statsPath(), stats);
        end

        function crackAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'crack_stats.xlsx');
            a = bms.analyzer.CrackAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'features', struct());
            tc.verifyClass(a, 'bms.analyzer.CrackAnalyzer');
            tc.verifyEqual(a.StatsFile, stats);
        end

        function tiltAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'tilt_stats.xlsx');
            a = bms.analyzer.TiltAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'wave_rs', struct());
            tc.verifyClass(a, 'bms.analyzer.TiltAnalyzer');
            tc.verifyEqual(a.Key, 'tilt');
            tc.verifyEqual(a.Subfolder, 'wave_rs');
        end

        function strainAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'strain_stats.xlsx');
            a = bms.analyzer.StrainAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'features', struct());
            tc.verifyClass(a, 'bms.analyzer.StrainAnalyzer');
            tc.verifyEqual(a.Key, 'strain');
            tc.verifyEqual(a.StatsFile, stats);
        end

        function accelerationAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'accel_stats.xlsx');
            a = bms.analyzer.AccelerationAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'wave', struct(), false);
            tc.verifyClass(a, 'bms.analyzer.AccelerationAnalyzer');
            tc.verifyEqual(a.Key, 'acceleration');
            tc.verifyFalse(a.SaveFigures);
        end

        function gnssAnalyzerCarriesPoints(tc)
            stats = fullfile(tempdir, 'gnss_stats.xlsx');
            a = bms.analyzer.GnssAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'features', struct(), {'G1','G2'});
            tc.verifyClass(a, 'bms.analyzer.GnssAnalyzer');
            tc.verifyEqual(a.Key, 'gnss');
            tc.verifyEqual(a.Points, {'G1','G2'});
        end

        function bearingDisplacementAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'bearing_displacement_stats.xlsx');
            a = bms.analyzer.BearingDisplacementAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'features_rs', struct());
            tc.verifyClass(a, 'bms.analyzer.BearingDisplacementAnalyzer');
            tc.verifyEqual(a.Key, 'bearing_displacement');
            tc.verifyEqual(a.Subfolder, 'features_rs');
        end

        function windAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'wind_stats.xlsx');
            a = bms.analyzer.WindAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'features', struct());
            tc.verifyClass(a, 'bms.analyzer.WindAnalyzer');
            tc.verifyEqual(a.Key, 'wind');
        end

        function earthquakeAnalyzerNormalizesKey(tc)
            stats = fullfile(tempdir, 'eq_stats.xlsx');
            a = bms.analyzer.EarthquakeAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'wave', struct());
            tc.verifyClass(a, 'bms.analyzer.EarthquakeAnalyzer');
            tc.verifyEqual(a.Key, 'earthquake');
        end

        function cableAccelerationAnalyzerCarriesSaveFlag(tc)
            stats = fullfile(tempdir, 'cable_accel_stats.xlsx');
            a = bms.analyzer.CableAccelerationAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'wave', struct(), false);
            tc.verifyClass(a, 'bms.analyzer.CableAccelerationAnalyzer');
            tc.verifyEqual(a.Key, 'cable_accel');
            tc.verifyFalse(a.SaveFigures);
        end

        function accelerationSpectrumAnalyzerCarriesSpectrumParams(tc)
            stats = fullfile(tempdir, 'accel_spec_stats.xlsx');
            a = bms.analyzer.AccelerationSpectrumAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, ...
                'wave', struct(), {'A1'}, [1.26 2.02 3.13], 0.2);
            tc.verifyClass(a, 'bms.analyzer.AccelerationSpectrumAnalyzer');
            tc.verifyEqual(a.Key, 'accel_spectrum');
            tc.verifyEqual(a.Points, {'A1'});
            tc.verifyEqual(a.Frequencies, [1.26 2.02 3.13]);
            tc.verifyEqual(a.Tolerance, 0.2);
        end

        function cableAccelerationSpectrumAnalyzerCarriesSpectrumParams(tc)
            stats = fullfile(tempdir, 'cable_accel_spec_stats.xlsx');
            a = bms.analyzer.CableAccelerationSpectrumAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, ...
                'wave', struct(), {'CS1'}, [0.8 1.6], 0.1);
            tc.verifyClass(a, 'bms.analyzer.CableAccelerationSpectrumAnalyzer');
            tc.verifyEqual(a.Key, 'cable_accel_spectrum');
            tc.verifyEqual(a.Points, {'CS1'});
            tc.verifyEqual(a.Frequencies, [0.8 1.6]);
            tc.verifyEqual(a.Tolerance, 0.1);
        end

        function dynamicStrainHighpassAnalyzerReadsConfig(tc)
            stats = fullfile(tempdir, 'dynamic_strain_highpass_stats.xlsx');
            cfg = struct();
            cfg.dynamic_strain = struct('output_dir', 'dyn_hp', 'fs', 50, 'fc', 0.2, 'whisker', 120);
            a = bms.analyzer.DynamicStrainHighpassAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'strain', cfg);
            tc.verifyClass(a, 'bms.analyzer.DynamicStrainHighpassAnalyzer');
            tc.verifyEqual(a.Key, 'dynamic_strain_highpass');
            tc.verifyEqual(a.OutputDir, 'dyn_hp');
            tc.verifyEqual(a.Fs, 50);
            tc.verifyEqual(a.Fc, 0.2);
            tc.verifyEqual(a.Whisker, 120);
        end

        function dynamicStrainLowpassAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'dynamic_strain_lowpass_stats.xlsx');
            a = bms.analyzer.DynamicStrainLowpassAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, 'strain', struct());
            tc.verifyClass(a, 'bms.analyzer.DynamicStrainLowpassAnalyzer');
            tc.verifyEqual(a.Key, 'dynamic_strain_lowpass');
        end

        function wimAnalyzerCarriesLegacyArguments(tc)
            a = bms.analyzer.WimAnalyzer('D:/data', '2026-01-01', '2026-01-31', '', 'WIM', struct());
            tc.verifyClass(a, 'bms.analyzer.WimAnalyzer');
            tc.verifyEqual(a.Key, 'wim');
            tc.verifyEqual(a.StatsFile, '');
        end
    end
end

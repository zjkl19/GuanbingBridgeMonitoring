classdef test_apply_lowpass < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setup(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'pipeline'));
        end
    end

    methods (Test)
        function interpolatesAcrossNanGapBeforeFiltering(tc)
            times = datetime(2026,1,1,0,0,0) + seconds([0 0 1:240]');
            vals = ones(size(times));
            nanMask = false(size(vals));
            nanMask(80:110) = true;
            vals(nanMask) = NaN;

            out = apply_lowpass(times, vals);

            tc.verifyTrue(all(isnan(out(nanMask))));
            tc.verifyLessThan(max(abs(out(~nanMask) - 1)), 1e-8);
        end

        function allNanInputIsReturnedUnchanged(tc)
            times = datetime(2026,1,1,0,0,0) + seconds((0:20)');
            vals = NaN(size(times));

            out = apply_lowpass(times, vals);

            tc.verifyEqual(out, vals);
        end

        function returnsUnchangedWhenInputLengthsMismatch(tc)
            times = datetime(2026,1,1,0,0,0) + seconds((0:20)');
            vals = (1:20)';

            tc.verifyWarning(@() apply_lowpass(times, vals), ...
                'apply_lowpass:SizeMismatch');
            warningState = warning('off', 'apply_lowpass:SizeMismatch');
            cleanup = onCleanup(@() warning(warningState)); %#ok<NASGU>
            out = apply_lowpass(times, vals);

            tc.verifyEqual(out, vals);
        end

        function restoresLeadingAndTrailingNanRuns(tc)
            times = datetime(2026,1,1,0,0,0) + seconds((0:240)');
            vals = ones(size(times));
            nanMask = false(size(vals));
            nanMask(1:12) = true;
            nanMask(230:241) = true;
            vals(nanMask) = NaN;

            out = apply_lowpass(times, vals);

            tc.verifyTrue(all(isnan(out(nanMask))));
            tc.verifyLessThan(max(abs(out(~nanMask) - 1)), 1e-8);
        end

        function returnsUnchangedWhenSamplingIntervalIsInvalid(tc)
            times = repmat(datetime(2026,1,1,0,0,0), 20, 1);
            vals = (1:20)';

            tc.verifyWarning(@() apply_lowpass(times, vals), ...
                'apply_lowpass:InvalidSamplingInterval');
            warningState = warning('off', 'apply_lowpass:InvalidSamplingInterval');
            cleanup = onCleanup(@() warning(warningState)); %#ok<NASGU>
            out = apply_lowpass(times, vals);

            tc.verifyEqual(out, vals);
        end

        function keepsRowVectorShape(tc)
            times = datetime(2026,1,1,0,0,0) + seconds(0:240);
            vals = ones(size(times));
            vals(50:70) = NaN;

            out = apply_lowpass(times, vals);

            tc.verifySize(out, size(vals));
            tc.verifyTrue(all(isnan(out(50:70))));
            tc.verifyLessThan(max(abs(out(~isnan(out)) - 1)), 1e-8);
        end
    end
end

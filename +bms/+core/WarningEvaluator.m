classdef WarningEvaluator
    %WARNINGEVALUATOR Shared warning-threshold evaluation helpers.

    methods (Static)
        function result = evaluateRange(lo, hi, lower2, upper2, lower3, upper3, subject)
            if nargin < 7, subject = ''; end
            result = bms.core.WarningEvaluator.baseResult(subject);
            if any(cellfun(@isempty, {lo, hi, lower2, upper2})) || any(isnan([lo, hi, lower2, upper2]))
                result.status = 'missing';
                result.message = 'threshold or value missing';
                return;
            end
            result.value = struct('min', lo, 'max', hi);
            result.thresholds = struct('lower2', lower2, 'upper2', upper2, 'lower3', lower3, 'upper3', upper3);
            if ~isempty(lower3) && ~isempty(upper3) && ~any(isnan([lower3, upper3])) && (lo < lower3 || hi > upper3)
                result.status = 'exceeded';
                result.level = 3;
            elseif lo < lower2 || hi > upper2
                result.status = 'exceeded';
                result.level = 2;
            else
                result.status = 'ok';
                result.level = 0;
            end
            result.exceeded = strcmp(result.status, 'exceeded');
            result.message = bms.core.WarningEvaluator.message(result);
        end

        function result = evaluateUpper(value, level2, level3, subject)
            if nargin < 4, subject = ''; end
            result = bms.core.WarningEvaluator.baseResult(subject);
            if isempty(value) || isempty(level2) || isnan(value) || isnan(level2)
                result.status = 'missing';
                result.message = 'threshold or value missing';
                return;
            end
            result.value = value;
            result.thresholds = struct('level2', level2, 'level3', level3);
            if ~isempty(level3) && ~isnan(level3) && value > level3
                result.status = 'exceeded';
                result.level = 3;
            elseif value > level2
                result.status = 'exceeded';
                result.level = 2;
            else
                result.status = 'ok';
                result.level = 0;
            end
            result.exceeded = strcmp(result.status, 'exceeded');
            result.message = bms.core.WarningEvaluator.message(result);
        end

        function results = evaluateRows(rows, minKey, maxKey, lower2, upper2, lower3, upper3, subjectField)
            if nargin < 8, subjectField = 'PointID'; end
            results = {};
            if istable(rows)
                rows = table2struct(rows);
            end
            for i = 1:numel(rows)
                row = rows(i);
                lo = bms.core.WarningEvaluator.fieldNumber(row, minKey);
                hi = bms.core.WarningEvaluator.fieldNumber(row, maxKey);
                subject = bms.core.WarningEvaluator.fieldText(row, subjectField);
                results{end+1} = bms.core.WarningEvaluator.evaluateRange(lo, hi, lower2, upper2, lower3, upper3, subject); %#ok<AGROW>
            end
        end

        function summary = summarize(results)
            if isstruct(results)
                results = num2cell(results);
            end
            summary = struct('count', 0, 'ok', 0, 'missing', 0, 'exceeded', 0, 'max_level', 0, 'exceeded_subjects', {{}});
            for i = 1:numel(results)
                r = results{i};
                if ~isstruct(r), continue; end
                summary.count = summary.count + 1;
                status = char(string(r.status));
                switch status
                    case 'ok'
                        summary.ok = summary.ok + 1;
                    case 'missing'
                        summary.missing = summary.missing + 1;
                    case 'exceeded'
                        summary.exceeded = summary.exceeded + 1;
                        summary.max_level = max(summary.max_level, double(r.level));
                        summary.exceeded_subjects{end+1} = char(string(r.subject)); %#ok<AGROW>
                end
            end
        end

        function result = baseResult(subject)
            result = struct();
            result.subject = char(string(subject));
            result.status = 'unknown';
            result.level = NaN;
            result.exceeded = false;
            result.value = [];
            result.thresholds = struct();
            result.message = '';
        end

        function msg = message(result)
            if strcmp(result.status, 'ok')
                msg = sprintf('%s within threshold', char(string(result.subject)));
            elseif strcmp(result.status, 'exceeded')
                msg = sprintf('%s exceeded level %d threshold', char(string(result.subject)), double(result.level));
            else
                msg = sprintf('%s warning evaluation %s', char(string(result.subject)), char(string(result.status)));
            end
        end

        function value = fieldNumber(row, fieldName)
            value = NaN;
            if isstruct(row) && isfield(row, fieldName)
                raw = row.(fieldName);
                if isnumeric(raw) && isscalar(raw)
                    value = raw;
                else
                    value = str2double(char(string(raw)));
                end
            end
        end

        function value = fieldText(row, fieldName)
            value = '';
            if isstruct(row) && isfield(row, fieldName)
                value = char(string(row.(fieldName)));
            end
        end
    end
end

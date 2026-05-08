classdef WimPreflight
    %WIMPREFLIGHT Fast WIM input checks before running SQL import.

    methods (Static)
        function result = check(root, startDate, endDate, cfg)
            if nargin < 4 || isempty(cfg), cfg = struct(); end
            result = struct();
            result.status = 'ok';
            result.errors = {};
            result.warnings = {};
            result.month_files = struct('month', {}, 'fmt', {}, 'bcp', {}, 'exists', {}, 'missing', {});
            result.input_root = '';
            result.file_prefix = 'HS_Data_';

            try
                src = bms.data.DataSourceFactory.wim(root, cfg);
                result.input_root = src.Root;
                result.file_prefix = src.filePrefix();
                files = src.monthFiles(startDate, endDate);
                for i = 1:numel(files)
                    missing = {};
                    if ~isfile(files(i).fmt), missing{end+1} = 'fmt'; end %#ok<AGROW>
                    if ~isfile(files(i).bcp), missing{end+1} = 'bcp'; end %#ok<AGROW>
                    rec = files(i);
                    rec.missing = missing;
                    result.month_files(end+1) = rec; %#ok<AGROW>
                    if ~isempty(missing)
                        result.warnings{end+1} = sprintf('WIM input missing for %s: %s. fmt=%s; bcp=%s', ...
                            files(i).month, strjoin(missing, '+'), files(i).fmt, files(i).bcp); %#ok<AGROW>
                    end
                end
            catch ME
                result.status = 'failed';
                result.errors{end+1} = ['WIM preflight failed: ' ME.message];
                return;
            end

            if ~isempty(result.errors)
                result.status = 'failed';
            elseif ~isempty(result.warnings)
                result.status = 'warning';
            end
        end
    end
end

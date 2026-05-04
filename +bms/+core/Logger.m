classdef Logger
    %LOGGER Lightweight JSON manifest writer used by the migration wrapper.

    methods (Static)
        function manifestPath = writeManifest(ctx, status, details)
            manifestPath = bms.app.ManifestWriter.write(ctx, status, details);
        end

        function files = listFiles(folder, pattern)
            files = {};
            if nargin < 2 || isempty(pattern), pattern = '*'; end
            if ~exist(folder, 'dir'), return; end
            d = dir(fullfile(folder, pattern));
            d = d(~[d.isdir]);
            files = cell(1, numel(d));
            for i = 1:numel(d)
                files{i} = fullfile(d(i).folder, d(i).name);
            end
        end

        function writeJson(path, data)
            folder = fileparts(path);
            if ~isempty(folder) && ~exist(folder, 'dir')
                mkdir(folder);
            end
            txt = jsonencode(data, 'PrettyPrint', true, 'ConvertInfAndNaN', true);
            fid = fopen(path, 'wt', 'n', 'UTF-8');
            if fid < 0
                error('Unable to write JSON file: %s', path);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
        end
    end
end

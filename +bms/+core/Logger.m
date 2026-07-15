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
            path = char(string(path));
            folder = fileparts(path);
            if isempty(folder)
                folder = pwd;
                path = fullfile(folder, path);
            elseif ~exist(folder, 'dir')
                mkdir(folder);
            end
            txt = jsonencode(data, 'PrettyPrint', true, 'ConvertInfAndNaN', true);
            % Status/manifests are polled while the MATLAB worker is writing.
            % Publish a complete same-directory temporary file so readers
            % never observe a truncated JSON document.
            tempPath = [tempname(folder) '.json.tmp'];
            tempCleanup = onCleanup(@() bms.core.Logger.deleteIfExists(tempPath)); %#ok<NASGU>
            fid = fopen(tempPath, 'wt', 'n', 'UTF-8');
            if fid < 0
                error('bms:Logger:JsonTempOpenFailed', ...
                    'Unable to open temporary JSON file: %s', tempPath);
            end
            closeFile = onCleanup(@() fclose(fid));
            written = fwrite(fid, txt, 'char');
            if written ~= numel(txt)
                error('bms:Logger:JsonShortWrite', ...
                    'Incomplete JSON write for %s: %d of %d characters.', ...
                    path, written, numel(txt));
            end
            clear closeFile;

            moved = false;
            moveMessage = '';
            moveId = '';
            for attempt = 1:10
                [moved, moveMessage, moveId] = movefile(tempPath, path, 'f');
                if moved
                    break;
                end
                pause(0.02);
            end
            if ~moved
                error('bms:Logger:JsonPublishFailed', ...
                    'Unable to publish JSON file %s (%s): %s', ...
                    path, moveId, moveMessage);
            end
        end
    end

    methods (Static, Access = private)
        function deleteIfExists(path)
            if exist(path, 'file') == 2
                delete(path);
            end
        end
    end
end

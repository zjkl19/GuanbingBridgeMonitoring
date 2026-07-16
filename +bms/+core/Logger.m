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
            % Keep machine-consumed status and manifest files compact.  Large
            % analysis manifests can contain thousands of artifact records;
            % pretty-print whitespace needlessly pushes the compiled runtime
            % toward its large-character-buffer boundary.
            txt = jsonencode(data, 'ConvertInfAndNaN', true);
            % A deployed compiler-runtime failure once returned an unterminated
            % JSON character vector at an exact 1 Mi-character boundary.  Do
            % not publish such a file merely because fwrite accepted every
            % character that jsonencode returned.
            try
                jsondecode(txt);
            catch ME
                error('bms:Logger:JsonEncodeInvalid', ...
                    'JSON encoding produced an invalid document for %s: %s', ...
                    path, ME.message);
            end
            % Status/manifests are polled while the MATLAB worker is writing.
            % Publish a complete same-directory temporary file so readers
            % never observe a truncated JSON document.
            tempPath = [tempname(folder) '.json.tmp'];
            tempCleanup = onCleanup(@() bms.core.Logger.deleteIfExists(tempPath));
            encodedBytes = unicode2native(txt, 'UTF-8');
            fid = fopen(tempPath, 'wb');
            if fid < 0
                error('bms:Logger:JsonTempOpenFailed', ...
                    'Unable to open temporary JSON file: %s', tempPath);
            end
            closeFile = onCleanup(@() fclose(fid));
            written = fwrite(fid, encodedBytes, 'uint8');
            if written ~= numel(encodedBytes)
                error('bms:Logger:JsonShortWrite', ...
                    'Incomplete JSON write for %s: %d of %d bytes.', ...
                    path, written, numel(encodedBytes));
            end
            clear closeFile;

            % Validate the bytes that will actually be published, not only
            % the in-memory encoder result.  This catches filesystem/runtime
            % short writes that still report a successful fwrite count.
            verifyFid = fopen(tempPath, 'rb');
            if verifyFid < 0
                error('bms:Logger:JsonVerifyOpenFailed', ...
                    'Unable to reopen temporary JSON file for verification: %s', tempPath);
            end
            closeVerify = onCleanup(@() fclose(verifyFid));
            publishedBytes = fread(verifyFid, Inf, '*uint8')';
            clear closeVerify;
            if ~isequal(publishedBytes, reshape(encodedBytes, 1, []))
                error('bms:Logger:JsonVerifyLengthMismatch', ...
                    'Temporary JSON verification byte mismatch for %s: %d of %d bytes.', ...
                    path, numel(publishedBytes), numel(encodedBytes));
            end
            try
                publishedText = native2unicode(publishedBytes, 'UTF-8');
                jsondecode(publishedText);
            catch ME
                error('bms:Logger:JsonVerifyInvalid', ...
                    'Temporary JSON verification failed for %s: %s', path, ME.message);
            end

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

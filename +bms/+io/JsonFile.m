classdef JsonFile
    %JSONFILE BOM-tolerant JSON reader for request/status contracts.

    methods (Static)
        function data = read(path)
            text = fileread(char(string(path)));
            if ~isempty(text) && double(text(1)) == 65279
                text(1) = [];
            end
            data = jsondecode(text);
        end

        function value = sha256(path)
            fid = fopen(char(string(path)), 'rb');
            if fid < 0
                error('BMS:JsonFile:OpenFailed', 'Cannot open file for hashing: %s', path);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            bytes = fread(fid, Inf, '*uint8');
            digest = java.security.MessageDigest.getInstance('SHA-256');
            digest.update(bytes);
            value = lower(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
        end
    end
end

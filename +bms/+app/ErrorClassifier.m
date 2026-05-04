classdef ErrorClassifier
    %ERRORCLASSIFIER Maps runtime failures to stable coarse error types.

    methods (Static)
        function errorType = classifyException(ME)
            if nargin < 1 || isempty(ME)
                errorType = '';
                return;
            end
            msg = '';
            ident = '';
            try, msg = char(ME.message); catch, msg = ''; end
            try, ident = char(ME.identifier); catch, ident = ''; end
            errorType = bms.app.ErrorClassifier.classifyText([ident ' ' msg]);
        end

        function errorType = classifyText(text)
            text = lower(char(string(text)));
            if isempty(strtrim(text))
                errorType = '';
            elseif contains(text, 'out of memory') || contains(text, '内存不足') || contains(text, 'memory')
                errorType = 'memory_error';
            elseif contains(text, 'wim:sql') || contains(text, 'sqlcmd') || contains(text, 'sql server') || contains(text, 'odbc')
                errorType = 'sql_error';
            elseif contains(text, 'wim:input') || contains(text, 'missingfmt') || contains(text, 'missingbcp') || contains(text, 'file missing') || contains(text, 'not found') || contains(text, 'no such file') || contains(text, '文件不存在') || contains(text, '未找到')
                errorType = 'input_missing';
            elseif contains(text, '无法读取') || contains(text, 'unable to read') || contains(text, 'read failed') || contains(text, '读取失败')
                errorType = 'read_failed';
            elseif contains(text, '无法识别的字段') || contains(text, 'unrecognized field') || contains(text, 'config') || contains(text, '配置') || contains(text, 'field')
                errorType = 'config_error';
            elseif contains(text, 'save') || contains(text, '无法保存') || contains(text, '.fig') || contains(text, '.jpg') || contains(text, '.emf') || contains(text, '.png')
                errorType = 'plot_save_failed';
            elseif contains(text, 'writetable') || contains(text, 'xlsx') || contains(text, 'excel') || contains(text, 'stats')
                errorType = 'stats_write_failed';
            else
                errorType = 'runtime_error';
            end
        end
    end
end

% 求解 fck*bc*l*(sqrt((2l+hb)^2+hb^2)-(2l+hb))/l <= 0.58*hw*tw*fy
clear; clc;

% 1. 常数定义
fck = 20.1;    % MPa
bc  = 400;     % mm
l   = 3400;    % mm
hw  = 560;     % mm
tw  = 16;      % mm
fy  = 345;     % MPa

% 为了简化，定义：
% A = fck*bc，  B = 0.58*hw*tw*fy
A = fck * bc;
B = 0.58 * hw * tw * fy;

% 2. 构造目标函数 f(hb)
%    f(hb) = A*( sqrt((2*l+hb)^2 + hb^2) - (2*l+hb) ) - B
f = @(hb) A*( sqrt( (2*l + hb).^2 + hb.^2 ) - (2*l + hb) ) - B;

% 3. 用 fzero 找到根（只关心正根，初始猜 2000 mm）
hb_root = fzero(f, 2000);

% 显示结果
fprintf('f(hb)=0 的正根大约为 hb = %.2f mm\n', hb_root);
fprintf('因此，满足不等式的物理解为： 0 ≤ hb ≤ %.2f (mm)\n', hb_root);

% 4. （可选）绘图检查
hb_vals = linspace(0, hb_root*1.2, 500);
plot(hb_vals, f(hb_vals), 'b-', 'LineWidth', 1.2); hold on;
plot([0, hb_root], [0,0], 'k--');                   % y=0 线
plot(hb_root, 0, 'ro', 'MarkerSize',8, 'LineWidth',1.5);
xlabel('h_b (mm)');
ylabel('f(h_b)');
title('f(h_b) 与 h_b 的关系');
grid on;
legend('f(h_b)','y=0','根位置','Location','Best');

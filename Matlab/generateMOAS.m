function moas = generateMOAS(sys,apx)
%% To find maximum output admissible set
%% User defined settings

% The algorithm includes all constraints until this iteration. This can be
% used to speed up convergence to t_star
skip_iter = 10;    

% Maximum value of t_star the algorithm can converge to. If
% max_iter<skip_iter, then all the constraints upto max_iter are included
max_iter = 100;  

% Data storage variables
save_data = true;
datafile = 'moas.mat';

%% Algorithm to generate MOAS

CX = sys.Cxu(:,1:sys.n);
CU = sys.Cxu(:,sys.n+1:end);
% a constraint is non-redundant if either lb or ub is unsatisfied

converged = zeros(length(sys.b_l),1);

options = optimoptions('linprog','display','off');

% Eliminate dynamics to improve speed        eta_x = Meq * eta_u
Meq = -inv(kron(sys.A,eye(apx.s))- ...
       kron(eye(sys.n),apx.Md'))*kron(sys.B,eye(apx.s));   

% Warm start: skip initial iterations
cons = kron(CX(sys.px+1:end,:),apx.tau0d')*Meq + kron(CU(sys.px+1:end,:),apx.tau0d');     
                    % state constraint at t=0 is not needed
cons_lb = sys.b_l(sys.px+1:end);
cons_ub = sys.b_u(sys.px+1:end);
time_indices = [-1 1];      
tauk = [apx.tau0d apx.Md*apx.tau0d];
for i = 1:skip_iter
    cons = [cons;         
            kron(CX,tauk(:,end)')*Meq + kron(CU,tauk(:,end)')];
    cons_lb = [cons_lb; sys.b_l];   
    cons_ub = [cons_ub; sys.b_u];
    time_indices(i+1,:) = ones(1,p); 
    tauk = [tauk apx.Md*tauk(:,end)];
end


while ~all(converged) && j<max_iter
    
    f1 = kron(CX,tauk(:,end)')*Meq + kron(CU,tauk(:,end)');            
    converged = run_cplex(f1,cons,cons_lb,cons_ub,sys.b_l,sys.b_u,options);
    
    if all(converged)
        t_star = j;
        break
    else
        cons = [cons; kron(CX(converged==0,:),tauk(:,end)')*Meq ...
                        + kron(CU(converged==0,:),tauk(:,end)')];   
                    
        cons_lb = [cons_lb; sys.b_l(converged==0,:)];   
        cons_ub = [cons_ub; sys.b_u(converged==0,:)];
        
        j = j+1;       
        
        
        for i = 1:sys.p
            if ~converged(i)
                time_indices(j+1,i) = 1;
            else
                % store -1 for all those constraints which are redundant
                time_indices(j+1,i) = -1;
            end
            
        end
    end
    
    tauk = [tauk apx.Md*tauk(:,end)];
end

%% change data representation into [eta_x;eta_u] = eta_z

% equality constraints (IC, dynamics)
Aeq = [kron(eye(sys.n),apx.tau0d') zeros(sys.n,sys.m*apx.s);
       kron(A,eye(apx.s))-kron(eye(sys.n),apx.Md'),kron(B,eye(apx.s))];
D = [eye(sys.n); zeros(sys.n*apx.s,sys.n)];

peq = length(Aeq(:,1));   % # of equality constraints
[Qeq,Req] = qr(Aeq');

% Change of variables: eta_z = Y*y + Z*z 
% Aeq*Z = 0
Y = Qeq(:,1:peq);
Z = Qeq(:,peq+1:end);
Req = Req(1:peq,1:peq);

% inequality constraints
Aineq = [];
lbineq = [];
ubineq = [];
for i = 1:length(time_indices)    
    ind = time_indices(i,:)>0;    
    Aineq  = [Aineq; [kron(CX(ind,:),(apx.Md^(i-1)*apx.tau0d)'),...
                kron(CU(ind,:),(apx.Md^(i-1)*apx.tau0d)')]*Z];
    lbineq = [lbineq; sys.b_l(ind)];
    ubineq = [ubineq; sys.b_u(ind)];
end

% eta_z = C*x0 + Z*z
C = Y/(Req')*D;

AiC = Aineq*C;
AiZ = Aineq*Z;

%% Data for parameterized constraint check
norms = zeros(t_star+1,1);

for i = 1:t_star+1
    norms(i) = norm(tauk(:,i)'* (apx.Md-eye(apx.s)));
end

Cs = kron(sys.Cxu,eye(apx.s));  % eta_w = Cs * eta_z

%% save data
moas.sys = sys;
moas.apx = apx;
moas.t_star = t_star;
moas.Aineq = Aineq;
moas.norms = norms;
moas.Cs = Cs;
moas.lbineq = lbineq;
moas.ubineq = ubineq;
moas.time_indices = time_indices;
moas.tauk = tauk;
moas.Z = Z;
moas.C = C;

if (save_data)    
    save(datafile,'moas')
end
end
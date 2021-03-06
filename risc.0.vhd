------------------------------------
-- Processeur RISC
-- THIEBOLT Francois le 09/12/04
------------------------------------

---------------------------------------------------------
-- Lors de la phase RESET, permet la lecture d'un fichier
-- instruction et un fichier donnees passe en parametre
--	generique.
---------------------------------------------------------

-- Definition des librairies
library IEEE;

-- Definition des portee d'utilisation
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;
use WORK.cpu_package.all;

-- Definition de l'entite
entity risc is

	-- definition des parametres generiques
	generic	(
		-- fichier d'initialisation cache instruction
		IFILE : string := "";

		-- fichier d'initialisation cache donnees
		DFILE : string := "" );

	-- definition des entrees/sorties
	port 	(
		-- signaux de controle du processeur
		RST			: in std_logic; -- actifs a l'etat bas
		CLK			: in std_logic );

end risc;

-- Definition de l'architecture du banc de registres
architecture behavior of risc is

	-- definition de constantes

	-- definitions de types/soustypes

	-- definition des ressources internes
	-- Registres du pipeline
	signal reg_EI_DI	: EI_DI;		-- registre pipeline EI/DI
	signal reg_DI_EX	: DI_EX;		-- registre pipeline DI/EX
	signal reg_EX_MEM	: EX_MEM;	-- registre pipeline EX/MEM
	signal reg_MEM_ER	: MEM_ER;	-- registre pipeline MEM/ER

	-- Ressources de l'etage EI
	signal reg_PC		: ADDR;			-- compteur programme format octet
	signal ei_next_pc	: PC;				-- pointeur sur prochaine instruction
	signal ei_inst		: INST;			-- instruction en sortie du cache instruction
	signal ei_halt		: std_logic;	-- suspension etage pipeline
	signal ei_flush	: std_logic;	-- vidange de l'etage

	-- Ressources de l'etage DI
	signal di_qa			: DATA;			-- sortie QA du banc de registres
	signal di_qb			: DATA; 			-- sortie QB du banc de registres
	signal di_imm_ext		: DATA;			-- valeur immediate etendue
	signal di_ctrl_di		: mxDI;			-- signaux de controle de l'etage DI
	signal di_ctrl_ex		: mxEX;			-- signaux de controle de l'etage EX
	signal di_ctrl_mem	: mxMEM;			-- signaux de controle de l'etage MEM
	signal di_ctrl_er		: mxER;			-- signaux de controle de l'etage ER
	signal di_halt			: std_logic;	-- suspension etage pipeline
	signal di_flush		: std_logic;	-- vidange de l'etage

	-- Ressources de l'etage EX

	-- Ressources de l'etage MEM

	-- Ressources de l'etage ER
	signal er_regd		: DATA;			-- donnees a ecrire dans le banc de registre
	signal er_adrw		: REGS;			-- adresse du registre a ecrire dans le banc

begin

-- ===============================================================
-- === Etage EI ==================================================
-- ===============================================================

------------------------------------------------------------------
-- instanciation et mapping du composant cache instruction
icache : entity work.memory(behavior)
			generic map ( DBUS_WIDTH=>CPU_DATA_WIDTH, ABUS_WIDTH=>CPU_ADR_WIDTH, MEM_SIZE=>L1_ISIZE,
								ACTIVE_FRONT=>L1_FRONT, FILENAME=>IFILE )
			port map ( RST=>RST, CLK=>CLK, RW=>'1', DS=>MEM_32, Signed=>'0', AS=>'1', Ready=>open,
								Berr=>open, ADR=>reg_PC, D=>(others => '0'), Q=>ei_inst );

------------------------------------------------------------------
-- Affectations dans le domaine combinatoire de l'etage EI
--

-- Incrementation du PC (format mot)
ei_next_pc <= reg_PC(PC'range)+1;

ei_halt <= '0';
ei_flush <= '0';

------------------------------------------------------------------
-- Process Etage Extraction de l'instruction et mise a jour de
--	l'etage EI/DI et du PC
EI: process(CLK,RST)
begin
	-- test du reset
	if (RST='0') then
		-- reset du PC
		reg_PC <= PC_DEFL;
	-- test du front actif d'horloge
	elsif (CLK'event and CLK=CPU_WR_FRONT) then
		-- Mise a jour PC
		reg_PC(PC'range)<=ei_next_pc;
		-- Mise a jour du registre inter-etage EI/DI
		reg_EI_DI.pc_next <= ei_next_pc;
		reg_EI_DI.inst <= ei_inst;
	end if;
end process EI;



-- ===============================================================
-- === Etage DI ==================================================
-- ===============================================================

------------------------------------------------------------------
-- instantiation et mapping du composant registres
regf : entity work.registres(behavior)
			generic map ( DBUS_WIDTH=>CPU_DATA_WIDTH, ABUS_WIDTH=>REG_WIDTH, ACTIVE_FRONT=>REG_FRONT )
			port map ( CLK=>CLK, W=>reg_MEM_ER.er_ctrl.regs_W, RST=>RST, D=>er_regd,
							 ADR_A=>reg_EI_DI.inst(RS'range), ADR_B=>reg_EI_DI.inst(RT'range),
							 ADR_W=>er_adrw, QA=>di_qa, QB=>di_qb );

------------------------------------------------------------------
-- Affectations dans le domaine combinatoire de l'etage DI
-- 

-- Calcul de l'extension de la valeur immediate
di_imm_ext(IMM'range) <= reg_EI_DI.inst(IMM'range);
di_imm_ext(DATA'high downto IMM'high+1) <= (others => '0') when di_ctrl_di.signed_ext='0' else
															(others => reg_EI_DI.inst(IMM'high));
-- Appel de la procedure contol
UC: control( reg_EI_DI.inst(OPCODE'range),
				 reg_EI_DI.inst(FCODE'range),
				 reg_EI_DI.inst(BCODE'range),
				 di_ctrl_di,
				 di_ctrl_ex,
				 di_ctrl_mem,
				 di_ctrl_er );
di_halt <= '0';
di_flush <= '0';

------------------------------------------------------------------
-- Process Etage Extraction de l'instruction et mise a jour de
--	l'etage DI/EX
DI: process(CLK,RST)
begin
	-- test du reset
	if (RST='0') then
		-- reset des controle du pipeline
		reg_DI_EX.ex_ctrl 	<= EX_DEFL;
		reg_DI_EX.mem_ctrl 	<= MEM_DEFL;
		reg_DI_EX.er_ctrl 	<= ER_DEFL;
	-- test du front actif d'horloge
	elsif (CLK'event and CLK=CPU_WR_FRONT) then
		-- Mise a jour du registre inter-etage DI/EX
		reg_DI_EX.pc_next		<= reg_EI_DI.pc_next;
		reg_DI_EX.rs			<= reg_EI_DI.inst(RS'range);
		reg_DI_EX.rt			<= reg_EI_DI.inst(RT'range);
		reg_DI_EX.rd			<= reg_EI_DI.inst(RD'range);
		reg_DI_EX.val_dec		<= reg_EI_DI.inst(VALDEC'range);
		reg_DI_EX.imm_ext		<= di_imm_ext;
		reg_DI_EX.jump_adr	<= reg_EI_DI.inst(JADR'range);
		reg_DI_EX.rs_read		<= di_qa;
		reg_DI_EX.rt_read		<= di_qb;
		-- Mise a jour des signaux de controle
		reg_DI_EX.ex_ctrl		<= di_ctrl_ex;
		reg_DI_EX.mem_ctrl	<= di_ctrl_mem;
		reg_DI_EX.er_ctrl		<= di_ctrl_er;
	end if;
end process DI;

end behavior;

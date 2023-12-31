﻿USE [Miracle]
GO
/****** Object:  StoredProcedure [dbo].[KW_205_10_v2]    Script Date: 22.03.2023 16:48:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		*Секрет*
-- Create date: 23.01.2020
-- Description:	Редактирование плана для филиалов
-- 22.03.2023 - Калашников В.Л. - обработка взаимоблокировки, мини рефакторинг
-- =============================================
CREATE PROCEDURE [dbo].[KW_205_10_v4]
	 @personId	int
	,@json		nvarchar(max)
AS
BEGIN 

	set nocount on;
	set transaction isolation level read uncommitted;

	declare
		 @matrix_title_id	int		= cast(JSON_VALUE(@json,'$.matrix_title_id')	as int)			-- айди матрицы
		,@matrix_category_id	int		= cast(JSON_VALUE(@json,'$.matrix_category_id') as int)			-- айди категории
		,@branch_id		int		= cast(JSON_VALUE(@json,'$.branch_id')		as int)			-- айди филиала
		,@category_type		char(1)		= cast(JSON_VALUE(@json,'$.category_type')	as char(1))		-- тип категории
		,@plan_sum		numeric(15, 2)	= cast(JSON_VALUE(@json,'$.plan_sum')		as numeric(15, 2))	-- план сумма
		,@plan_piece		int		= cast(JSON_VALUE(@json,'$.plan_piece')		as int)			-- план штук
		,@clear_plan_sum	char(1)		= cast(JSON_VALUE(@json,'$.clear_plan_sum')	as char(1))		-- признак очистки суммы
		,@clear_plan_piece	char(1)		= cast(JSON_VALUE(@json,'$.clear_plan_piece')	as char(1))		-- признак очистки штук
		,@retry_counter		int		= 3									-- счетчик попыток
	
	-- обработка взаимоблокировки
	while (@retry_counter > 0)
	begin
		begin try

			-- начало транзакции
			begin transaction;

				-- Обновление плана на матрицу
				update Miracle.dbo.MatrixBranchCategoryTypePlan 
				set planSum = @plan_sum
				   ,planPiece = @plan_piece
				where matrixTitleId = @matrix_title_id and 
				      branchId = @branch_id and 
				      categoryType = @category_type and 
				      matrixCategoryId = @matrix_category_id

				-- Иначе добавление
				if @@ROWCOUNT = 0
				begin
					insert into Miracle.dbo.MatrixBranchCategoryTypePlan (
						 matrixTitleId
						,branchId
						,categoryType
						,matrixCategoryId
						,planSum
						,planPiece
					)
					values (
						 @matrix_title_id
						,@branch_id
						,@category_type
						,@matrix_category_id
						,@plan_sum
						,@plan_piece
					)
				end

			-- конец транзакции
			commit transaction;

			-- выходим из цикла
			set @retry_counter = 0;

		end try
		begin catch

			-- уменьшение счетчика
			set @retry_counter -= 1;

			if (@retry_counter > 0 and ERROR_NUMBER() in (1205))
			begin

				-- если ошибка активной транзакции - откат
				if XACT_STATE() = -1 rollback transaction;

				-- задержка
				waitfor delay '00:00:00.001';

			end

		end catch
	end

	-------------------------------------------------------------------------------------

	-- Очищяем суммы планов для сотрудников
	if (@clear_plan_sum = '1') 
	begin
		update mbc 
		set mbc.planUserSum = null 
		from Miracle.dbo.MatrixBranchCustomer mbc
		where mbc.branchId = @branch_id and 
		      mbc.matrixTitleId = @matrix_title_id and 
		      mbc.matrixCategoryId = @matrix_category_id 
	end

	-- Очищяем штуки планов для сотрудников
	if (@clear_plan_piece = '1') 
	begin
		update mbc 
		set mbc.planUserPiece = null 
		from Miracle.dbo.MatrixBranchCustomer mbc
		where mbc.branchId = @branch_id and
		      mbc.matrixTitleId = @matrix_title_id and 
		      mbc.matrixCategoryId = @matrix_category_id 
	end
END

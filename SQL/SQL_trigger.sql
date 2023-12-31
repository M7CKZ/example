﻿USE [Miracle]
GO
/****** Object:  Trigger [dbo].[Tr_DoubleCustomer_After_Insert_Update]    Script Date: 08.02.2023 14:03:25 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ======================================================================================
-- Author:		Калашников В.Л.
-- Description:	Удаление производителя из приоритетов производителей автозаказа
-- Create Date: 05.12.2022

/*
 При выключении дубля у товара может быть настроен приоритет производителя
 производитель должен удаляться в том случае, если ни у одного товара из дубля
 не существует такого производителя, чтоб в случае добавления нового товара в дубль, 
 у которого такой производитель есть, к нему не применялись настройки оставшиеся от прошлого товара
*/
-- ======================================================================================
ALTER TRIGGER [dbo].[Tr_DoubleCustomer_After_Insert_Update] 
   ON  [dbo].[DoubleCustomer] 
   AFTER UPDATE
AS 
BEGIN
 
 ---------------------------------------------------------------------------

 SET NOCOUNT ON;
 set transaction isolation level read uncommitted;

 ---------------------------------------------------------------------------

 -- копия добавляемой таблицы только с удаляемыми товарми
 select top 0 * into #tmpDeletedDoubles from inserted

 -- разрешаем добавление уникального идентификатора в таблицу
 set identity_insert #tmpDeletedDoubles on;

 -- только удаляемые позиции из дубля
 insert into #tmpDeletedDoubles (
    DoubleCustomerId
   ,ParentDoubleCustomerId
   ,DrugId
   ,FormId
   ,ParentCustomerId
   ,Disable
 )
 select i.DoubleCustomerId
       ,i.ParentDoubleCustomerId
       ,i.DrugId
       ,i.FormId
       ,i.ParentCustomerId
       ,i.Disable
 from inserted i 
 join deleted d 
 on i.DrugId = d.DrugId and 
    i.FormId = d.FormId and 
    i.[Disable] != d.[Disable]
 where i.[Disable] = '1'

 -- запрещаем добавление уникального идентификатора в таблицу
 set identity_insert #tmpDeletedDoubles off;

 ---------------------------------------------------------------------------

 -- если есть удаляемые из дубля товары
 if exists (select 1 from #tmpDeletedDoubles)
 begin

  ---------------------------------------------------------------------------

  -- все товары относящиеся к дублю, кроме удаляемых
  declare @tblOtherDoubles table (
    doubleId	   	int     -- родитель
   ,parentDoubleId 	int     -- ссылка на родителя
   ,drugId 		int     -- идентификатор наименования товара
   ,formId		int     -- идентификатор формы выпуска товара
   ,[Disable]	   	char(1) -- признак отключение 
  )

  -- все товары относящиеся к дублю + их производители, кроме удаляемых
  declare @tblOtherDoublesFabrList table (
    doubleId	   	int -- родитель
   ,parentDoubleId 	int -- ссылка на родителя
   ,drugId		int -- идентификатор наименования товара
   ,formId		int -- идентификатор формы выпуска товара
   ,fabrId		int -- идентификатор производителя
  )

  -- список товар и производителей по удаляемым из дубля товарам
  declare @tblDeletedDoublesFabrList table (
    doubleId	   	int -- родитель
   ,parentDoubleId 	int -- ссылка на родителя
   ,drugId		int -- идентификатор наименования товара
   ,formId		int -- идентификатор формы выпуска товара
   ,fabrId		int -- идентификатор производителя
  )

  -- итоговый список удаляемых производителей из приоритетов производителей с группировкой по дублю
  declare @tblFabrListToDelete table (
    fabrId		int -- идентификатор наименования товара
   ,parentDoubleId 	int -- ссылка на родителя
  )

  ---------------------------------------------------------------------------

  -- список не удаляемых дублей
  insert into @tblOtherDoubles (
	 doubleId
	,parentDoubleId
	,drugId
	,formId
	,[Disable]
  )
  select dc.DoubleCustomerId
	,dc.ParentDoubleCustomerId
	,dc.drugId
	,dc.formId
	,dc.[Disable]
  from Miracle.dbo.DoubleCustomer dc
  left join Miracle.dbo.DoubleDefault dd 
  on dd.DoubleDefaultId = dc.DoubleDefaultId
  where 
  dc.ParentDoubleCustomerId in (
	select i.ParentDoubleCustomerId 
	from inserted i
	group by i.ParentDoubleCustomerId
  )
  and not exists (
	select 1
	from #tmpDeletedDoubles tdd
	where tdd.DrugId = dc.DrugId and 
	      tdd.FormId = dc.FormId
  )

  ---------------------------------------------------------------------------

  -- заполняем не удаляемые товары и их производители
  insert into @tblOtherDoublesFabrList (
	 drugId
	,formId
	,fabrId
  )
  select tpl.drugId
	,tpl.formId
	,r.fabrId
  from @tblOtherDoubles tpl
  join Megapress.dbo.Registry r 
  on r.drugId = tpl.drugId and 
     r.formId = tpl.formId and 
     r.FLAG = 0
  where tpl.Disable = '0'
  group by tpl.drugId
	  ,tpl.formId
	  ,r.fabrId

  -- проставление род. данных по не удаляемым дублям
  update t
  set doubleId = tb.doubleId
     ,parentDoubleId = tb.parentDoubleId
  from @tblOtherDoublesFabrList t
  join @tblOtherDoubles tb 
  on t.drugId = tb.drugId and 
     t.formId = tb.formId

  ---------------------------------------------------------------------------

  -- удаляемые дубли и их производители
  insert into @tblDeletedDoublesFabrList (
	 drugId
	,formId
	,fabrId
  )
  select tdd.drugId
	,tdd.formId
	,r.fabrId
  from #tmpDeletedDoubles tdd
  join Megapress.dbo.Registry r
  on r.drugId = tdd.drugId and 
     r.formId = tdd.formId and 
     r.FLAG = 0
  group by tdd.drugId
	  ,tdd.formId
	  ,r.fabrId

  -- проставление род. данных для удаляемых дублей
  update t
  set doubleId = tdd.DoubleCustomerId
     ,parentDoubleId = tdd.ParentDoubleCustomerId
  from @tblDeletedDoublesFabrList t
  join #tmpDeletedDoubles tdd  
  on t.drugId = tdd.drugId and 
     t.formId = tdd.formId

  ---------------------------------------------------------------------------

  -- собираем список производителей, которые есть только у удаляемых товаров из дубля
  insert into @tblFabrListToDelete (
	 fabrId
	,parentDoubleId
  )
  select t.fabrId
	,parentDoubleId
  from @tblDeletedDoublesFabrList t
  group by t.fabrId
	  ,t.parentDoubleId
  EXCEPT
  select t.fabrId
	,t.parentDoubleId
  from @tblOtherDoublesFabrList t
  group by t.fabrId
	  ,t.parentDoubleId

  ---------------------------------------------------------------------------

  -- если есть удаляемые производители
  if exists (select 1 from @tblFabrListToDelete)
  begin
  
   -- фактически удаляем из приоритетов - производителей, которых нет у других товаров из дубля
   delete azfp
   from Miracle.dbo.AutoZakazFabrPriority azfp
   join inserted i on i.ParentCustomerId = azfp.parentCustomerId 
   join (
    select doubleId
	  ,parentDoubleId
	  ,drugId
	  ,formId
    from @tblOtherDoubles
    UNION
    select DoubleCustomerId	  as doubleId
	  ,ParentDoubleCustomerId as parentDoubleId
	  ,DrugId		  as drugId
	  ,FormId		  as formId
    from #tmpDeletedDoubles
   ) tpl 
   on tpl.drugId = azfp.drugId and 
      tpl.formId = azfp.formId and 
      tpl.doubleId = tpl.parentDoubleId
   where azfp.fabrId in (
	select fabrId 
	from @tblFabrListToDelete t
	where t.parentDoubleId = tpl.parentDoubleId
   )

   -- TODO логирование?

  end

  /*
  ---------------------------------------------------------------------------

  -- список товаров
 ;with cteAllDoubles as (
    select  doubleId
	 	   ,parentDoubleId
		   ,drugId
		   ,formId
		   ,[Disable]
	 from @tblOtherDoubles
	 UNION
	 select DoubleCustomerId	   as doubleId
		   ,ParentDoubleCustomerId as parentDoubleId
		   ,DrugId				   as drugId
		   ,FormId				   as formId
		   ,[Disable]			   as [Disable]
	 from #tmpDeletedDoubles
  ), 
  -- список выключенных полностью дублей
  cteDeletingDoubles as (
    select c.drugId
	      ,c.formId
	from cteAllDoubles c
	where not exists (
	 select 1 from cteAllDoubles c2 where c2.parentDoubleId = c.parentDoubleId and c2.[Disable] = '0'
	) and c.parentDoubleId = c.doubleId
	group by c.drugId, c.formId
  )

  -- удаляем все приоритеты у дубля, если он полностью выключен
  delete azfp
  from Miracle.dbo.AutoZakazFabrPriority azfp
  join cteDeletingDoubles c on c.drugId = azfp.drugId and c.formId = azfp.formId
  where azfp.parentCustomerId = (select top 1 parentCustomerId from inserted group by parentCustomerId) 

  ---------------------------------------------------------------------------
  */

 end

 drop table #tmpDeletedDoubles

END

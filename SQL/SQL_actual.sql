/*
	Примерно к такому написанию кода я пришел на данный момент
*/

USE [Miracle]
GO
/****** Object:  StoredProcedure [dbo].[KW_74_25_v2]    Script Date: 18.01.2023 16:17:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Калашников В.Л.
-- Create date: 08.12.2022
-- Description:	Заказ товара, который не был заказан ранее
-- 22.12.2022 - *Секрет* V2 - добавлен вывод комментариев при ручном редактировании заказа
-- 26.12.2022 - *Секрет* V2 - добавлена проверка на присутствие предложений у поставщиков
------------------------------------------------
/*
Входящие параметры:
-- кол-во к заказу
order int,
-- идентификатор заказа
auto_zakaz_order_title_id int,
-- список идентификаторов рассчитанной потребности
products: [
 {
  auto_zakaz_data_id
 }
]

*/
-- =============================================
ALTER PROCEDURE [dbo].[KW_74_25_v2]
 @personId int,
 @json nvarchar(max)
AS
BEGIN

 set nocount on;
 set transaction isolation level read uncommitted;

 --------------------------------------------------------------------------------------------

 declare
  @autoZakazOrderTitleId 	int = JSON_VALUE(@json, '$.auto_zakaz_order_title_id')	 	-- идентификатор заказа
 ,@order			int = JSON_VALUE(@json, '$.order')				-- кол-во штук к заказу

 --------------------------------------------------------------------------------------------

-- список анализируемых товаров к заказу
 declare @tblProducts dbo.IntList


 -- список необходимых данных для расчета
 declare @tblDataList table (
   autoZakazDataId	int		-- идетнтификатор товара из расчета потребности
  ,[data]		nvarchar(max) 	-- предложения поставщиков, рекомендованные поставщики
 )

 -- список товаров с их заказанными идентификаторами
 declare @tblOrderIdsList table (
   autoZakazOrderDataId int -- идентификатор товара в размещенном заказе
  ,autoZakazDataId	int -- идетнтификатор товара из расчета потребности
 )

 -- список предложений к заказу
 declare @tblOffersList table (
   auto_zakaz_data_id 	int 		-- идетнтификатор товара из расчета потребности
  ,reg_id		int 		-- идентификатор товар с учетом производителя
  ,drug_id		int 		-- идентификатор наименования товара
  ,form_id		int 		-- идентификатор формы выпуска
  ,fabr_id		int 		-- идентификатор производителя
  ,distr_id_web		int 		-- идентификатор поставщика веб
  ,distr_price_id	bigint 		-- идентификатор прайс-листа
  ,distr_price		numeric (15, 2) -- цена
  ,distr_ost		int		-- остатки
  ,distr_min_zakaz    	smallint	-- минимальный заказ
  ,distr_ratio		smallint	-- кратность
  ,distr_name		varchar(150)	-- наименования поставщика
  ,distr_price_fabr   	numeric (15, 2) -- цена производителя
  ,k_eff		numeric (15, 5)	-- коэффициент эффективности
  ,drug_name		varchar(255)	-- наименование товара
  ,form_name		varchar(255)	-- наименование формы
  ,fabr_name		varchar(255)	-- наименование производителя
 )

 -- список рекомендованных маркетинговых поставщиков
 declare @tblRecommendedSuppliers table (
   reg_id   int	-- идентификатор товар с учетом производителя
  ,drug_id  int	-- идентификатор наименования товара
  ,form_id  int	-- идентификатор формы выпуска
  ,distr_id int -- идентификатор поставщика
 )

 -- заказанный товар
 declare @tblOrder table (
    auto_zakaz_data_id	int	-- идетнтификатор товара из расчета потребности
   ,price_id		bigint 	-- идентификатор прайс-листа
 )

 -- список комментариев при редактировании заказа
 declare @commentsWhenEditingOrder table (
   type_comments int -- тип комментария (1 - остаток, 2 - мин заказ, 3 - кратность, 4 - присутствие предложений у поставщиков)
  ,limitation	 int -- установленный лимит ограничения (кратность, минимальный заказ, остаток)
)

 --------------------------------------------------------------------------------------------

 -- собираем список товаров
 insert into @tblProducts(
	[value]
 )
 select auto_zakaz_data_id
 from openjson(@json, '$.products')
 with (
   auto_zakaz_data_id varchar(20) '$.auto_zakaz_data_id'
 )
 option (optimize for unknown)

 --------------------------------------------------------------------------------------------

 -- собираем необходимые данные для расчета
 insert into @tblDataList(
    autoZakazDataId
   ,[data]
 )
 select  az.AutoZakazDataId
	,az.OffersAndSuppliers
 from Miracle.dbo.AutoZakazExtraData az with (index = Ind1)
 join @tblProducts t 
 on t.[value] = az.AutoZakazDataId

 --------------------------------------------------------------------------------------------

 -- собираем список предложений
 insert into @tblOffersList(
   auto_zakaz_data_id
  ,reg_id
  ,drug_id
  ,form_id
  ,fabr_id
  ,distr_id_web
  ,distr_price_id
  ,distr_price
  ,distr_ost
  ,distr_min_zakaz
  ,distr_ratio
  ,distr_name
  ,distr_price_fabr
  ,k_eff
  ,drug_name
  ,form_name
  ,fabr_name
 )
 select oa.*
 from @tblDataList t
 outer apply (
  select *
  from openjson([data], '$.offers')
  with (
    auto_zakaz_data_id int
   ,reg_id		int
   ,drug_id		int
   ,form_id		int
   ,fabr_id		int
   ,distr_id_web	int
   ,distr_price_id	bigint
   ,distr_price		numeric (15, 2)
   ,distr_ost		int
   ,distr_min_zakaz  	smallint
   ,distr_ratio		smallint
   ,distr_name		varchar(150)
   ,distr_price_fabr 	numeric (15, 2)
   ,k_eff 		numeric (15, 5)
   ,drug_name		varchar(255)
   ,form_name		varchar(255)
   ,fabr_name		varchar(255)
  )
 ) oa

 --------------------------------------------------------------------------------------------

 -- заполнение рекомендованных поставщиков
 insert into @tblRecommendedSuppliers(
    reg_id
   ,drug_id
   ,form_id
   ,distr_id
 )
 select oa.*
 from @tblDataList
 outer apply (
  select *
  from openjson([data], '$.recommended_suppliers')
  with (
    reg_id   int
   ,drug_id  int
   ,form_id  int
   ,distr_id int
  )
 ) oa
 where oa.reg_id is not null

 --------------------------------------------------------------------------------------------

 -- пытаемся разместить на рекомендованного поставщика
 if exists (select 1 from @tblRecommendedSuppliers)
 begin
	 insert into @tblOrder (
	    auto_zakaz_data_id
	   ,price_id
	 )
	 select top 1 t.auto_zakaz_data_id
		     ,t.distr_price_id
	 from @tblOffersList t
	 join @tblRecommendedSuppliers tr 
	 on tr.drug_id = t.drug_id and 
	    tr.form_id = t.form_id and 
	    tr.distr_id = t.distr_id_web
	 where t.distr_ost >= @order and 
	       @order >= t.distr_min_zakaz and 
	       ((@order % t.distr_ratio) = 0)
 end

 -- если не получилось на рекомендованного
 if not exists (select 1 from @tblOrder)
 begin
	insert into @tblOrder (
	    auto_zakaz_data_id
	   ,price_id
	 )
	select top 1 t.auto_zakaz_data_id
		    ,t.distr_price_id
	from @tblOffersList t
	where t.distr_ost >= @order and
	      @order >= t.distr_min_zakaz and 
	      ((@order % t.distr_ratio) = 0)
 end

----------------------------------------------------------------------------------------------
--------------- Добавление комментариев при редактировании заказа ----------------------------
-- (не мое)

-- Проверка на присутствие предложений у поставщиков
 if exists(select 1 from @tblOffersList)
 begin

 -- Проверка остатка для поставщиков
 if not exists (select 1 from @tblOffersList where distr_ost >= @order)
  begin
    insert into @commentsWhenEditingOrder(
		 type_comments
	   	,limitation
	)
    select 1 			as type_comments
	  ,max(t.distr_ost) 	as limitation
    from @tblOffersList t
  end

 -- Проверка на минимальный заказ
 if not exists (select 1 from @tblOffersList where @order >= distr_min_zakaz)
  begin
    insert into @commentsWhenEditingOrder(
	    type_comments
	   ,limitation
	)
    select 2			  as type_comments
	  ,min(t.distr_min_zakaz) as limitation
    from @tblOffersList t
  end

 -- Проверка на кратность
 if not exists (select 1 from @tblOffersList where (@order % distr_ratio) = 0)
  begin
    insert into @commentsWhenEditingOrder(
	    type_comments
	   ,limitation
	)
    select 3			as type_comments
	  ,min(distr_ratio) 	as limitation
    from @tblOffersList t
  end
end

 -- Если нет предложений у поставщиков
 else
   begin
     insert into @commentsWhenEditingOrder(
		 type_comments
		,limitation
	 )
     select 4 as type_comments
	   ,0 as limitation
   end

 --------------------------------------------------------------------------------------------

 -- наличие заказа
 if exists (select 1 from @tblOrder)
 begin

	 -- сбрасываем коммент, т.к нужен коммент отредактирован пользователем - это parent_auto_zakaz_data_id = -1
	 update azd
	 set commentIds = null
	 from Miracle.dbo.AutoZakazData azd
	 join @tblProducts tp 
	 on tp.[value] = azd.autoZakazDataId

	 -- добавляем в список заказанных позиций
	 insert Miracle.dbo.AutoZakazOrderData (
	    autoZakazOrderTitleId
	   ,autoZakazDataId
	   ,zakazToOrder
	   ,price
	   ,distrId
	   ,regId
	   ,priceId
	   ,priceFabr
	   ,canBeExcluded
	   ,parentAutoZakazDataId
	 )
	 --------------------------------------------
	 output  inserted.autoZakazOrderDataId
		,inserted.autoZakazDataId
	 into @tblOrderIdsList (
	   autoZakazOrderDataId
	  ,autoZakazDataId
	 )
	 --------------------------------------------
	 select @autoZakazOrderTitleId 	as autoZakazOrderTitleId
	       ,tp.auto_zakaz_data_id  	as autoZakazDataId
	       ,@order			as zakazToOrder
	       ,tp.distr_price		as price
	       ,tp.distr_id_web		as distrId
	       ,tp.reg_id		as regId
	       ,tp.distr_price_id	as priceId
	       ,tp.distr_price_fabr	as priceFabr
	       ,'1'			as canBeExcluded
	       ,'-1'			as parentAutoZakazDataId
	 from @tblOrder t
	 join @tblOffersList tp 
	 on t.price_id = tp.distr_price_id
	 where not exists (
	  select 1
	  from Miracle.dbo.AutoZakazOrderData azod
	  where azod.autoZakazOrderTitleId = @autoZakazOrderTitleId and 
	        azod.autoZakazDataId = tp.auto_zakaz_data_id and 
	        azod.donorBranchId is null
	 )

 end

 --------------------------------------------------------------------------------------------

 if exists (select 1 from @tblOrder)
 begin

	 -- возвращаем результат
	 select o.autoZakazOrderDataId		as auto_zakaz_order_data_id_order 	-- идентификатор товара в заказе
		   ,tl.auto_zakaz_data_id	as auto_zakaz_data_id			-- идентификатор потребности товара
		   ,tl.reg_id			as reg_id				-- идентификатор товара с учетом производителя
		   ,tl.drug_id			as drug_id				-- идентификатор наименования товара
		   ,tl.form_id			as form_id				-- идентификатор формы выпуска
		   ,tl.distr_id_web		as distr_id				-- идентификатор поставщика
		   ,tl.distr_price_id		as price_id				-- идентификатор прайс-листа
		   ,tl.drug_name		as drug					-- наимнование товара
		   ,tl.form_name		as form					-- наименование формы
		   ,tl.fabr_name		as fabr					-- наименование производителя
		   ,tl.distr_price		as price				-- цена предложения
		   ,tl.distr_price		as offer_price				-- цена предложения
		   ,tl.distr_price_fabr		as price_fabr				-- цена производителя
		   ,@order			as [order]				-- заказ
		   ,@order * tl.distr_price	as sum_order				-- сумма заказа по товару
		   ,null			as comment_ids				-- комментарии - сбрасываем
		   ,'-1'			as parent_auto_zakaz_data_id	   	-- в этом случае считается как коммент - отредактирован пользователем
		   ,tl.k_eff			as k_eff				-- коэффициент эффективности
		   ,'1'				as isCountKeff				-- признак того, что нужно считать эффективность
		   ,'1'				as can_be_excluded			-- признак того, что товар может быть исключен из заказа по ограничению
		   ,tl.distr_ratio		as distr_ratio				-- кратность заказанного поставщика
		   ,tl.distr_min_zakaz		as distr_min_zakaz			-- минимальный заказ по поставщику
		   ,tl.distr_ost		as distr_ost				-- остаток у поставщика
		   ,tl.distr_name		as distr				-- наименования поставщика
	 from @tblOrder t
	 join @tblOffersList tl 
	 on t.price_id = tl.distr_price_id and 
	    t.auto_zakaz_data_id = tl.auto_zakaz_data_id
	 join @tblOrderIdsList o
	 on tl.auto_zakaz_data_id = o.autoZakazDataId

 end
 else
 begin

  -- иначе если заказ не разместился возвращаем комментарии почему
  select 0 as success

  select type_comments 	-- тип коммента
	,limitation	-- установленный лимит ограничения (кратность, минимальный заказ, остаток)
  from @commentsWhenEditingOrder

 end

 --------------------------------------------------------------------------------------------

END

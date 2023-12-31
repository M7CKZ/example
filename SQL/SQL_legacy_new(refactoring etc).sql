﻿/*
 Оптимизация, переработка legacy, рефакторинг, доработки и пр. - код работал медленно и зашел в тупик,
 было не возможно внести необходимые изменения без последствий, после переработки можно спокойно
 вносить прочие новшества, изменения
*/

USE [Miracle]
GO
/****** Object:  StoredProcedure [dbo].[KW_order_core_v13]    Script Date: 18.01.2023 16:22:05 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ===========================================================================
-- Author: 	*Секрет*
-- Create date: 09.10.2019
-- Description:	Заполнение заказа (#tmpOrder) в зависимости от параметров
-- ===========================================================================
--	  История изменений
-- ===========================================================================

--    	  ..........

--	  21.09.2022 - (v9) Калашников В.Л   - корректировки по ограничению, фикс рекомендованных поставщиков, 
--					       заполнения списка поставщиков через KW_GetCustomerDistrs_v1
--	  22.09.2022 - (v9)  Калашников В.Л. - уменьшение товара к заказу к остатку поставщика с учетом кратности, минимального заказа
--    	  23.09.2022 - (v10) ...  ТЗ №14900б - условие для выбора рекомендованного поставщика в автозаказе
--	  26.09.2022 - (v10) Калашников В.Л. - доп. оптимизация по маркетингу, упразднение маркетинговых товаров не попавших в прайс. 
--					       Создание-удаление таблиц в момент отсутствия в них необходимости. Понятные названия таблиц.
--	  06.10.2022 - (v10) Калашников В.Л. - добавление перезаказа с помощью @type_update в ветке drugId + formId
--		       (v11) Калашников В.Л. - упразднение ветки - @parentDF_or_regId = '2' ввиду отсутствия необходимости,
--					     - полная переработка структуры процедуры, рефакторинг
--	  12.10.2022 - (v11) Калашников В.Л. - признак возможности исключения товара из заказа при ограничении - canBeExcluded в #tmpOrder
--	  19.10.2022			     - сохранение идентификатора профиля автозаказа AutoZakazProfileId через #tmpBranch
--	  21.10.2022			     - корректировки в определении неликвидов
--	  25.10.2022 - (v12) Калашников В.Л. - переработан блок размещения товаров в заказе
--	  31.10.2022 - (v13) Калашников В.Л. - переработан блок заполнения таблицы товаров с рассчитанной потребностью матричными товарами
--					     - прочие структурные изменения, оптимизация некоторых моментов
--	  03.11.2022 - (v13) Калашников В.Л. - игнор рекомендованных поставщиков АСНА, если их цена превышает минимальную на процент из настроек
--	  09.11.2022 - (v13) Калашников В.Л. - перерботан блок ограничения заказа по новым принципам.
--	  10.11.2022 - (v13) Калашников В.Л. - корректировки блока уменьшения лишних перемещений
--					     - переработан блок размещения перемещений в заказе
--	  23.11.2022 - (v13) Калашников В.Л. - добавлен блок проставления макретинговой/матричной потребности
--					     - удаление лишних товаров без потребностей, размещение дублей с учетом маркетинга/матриц
--	  28.11.2022 - (v13) Калашников В.Л. - при перезаказе по актуальному прайсу используем сумму ограничения обновляемого автозаказа
--	  05.12.2022 - (v13) Калашников В.Л. - переработка блока проставления комментариев к анализируемым товарам с учетом дублей
--					     - проставление коммента ограничения заказа у не попавших в заказ товаров по другой причине
--	  12.12.2022 - (v13) Калашников В.Л. - Блок заполнения дополнительных данных с сохранением предложений, рекомендованных поставщиков товара в бд
--	  26.12.2022 - (v13) Калашников В.Л. - сохранение кол-ва штук по позиции попавшее в ограничение
--
-- ===========================================================================
-- Список процедур откуда вызывается данная процедура
-- ===========================================================================
--
-- AutoZakazCreateOrder
-- KW_114_3
-- KW_114_6
-- KW_order_update
--
--------------------------------------
-- KW_74_21 -> KW_order_update -> KW_order_core
-- KW_703_4 -> KW_order_update -> KW_order_core
--------------------------------------
-- (не используется)
-- OrderUpdate_v1
-- KW_110_6
--------------------------------------

-- ===========================================================================
-- Список таблиц, которые создаются извне.
-- ===========================================================================
--
-- #tmpOrder		 -- итоговая таблица с товарами, попавшими в автозаказ
-- #tmpBranch		 -- список филиалов
-- #tmpSrokG		 -- сроки годности по филиалам
-- #tmpZakaz		 -- список анализируемых товаров с рассчитанной потребностью
-- #tmpDistrPriority 	 -- Поставщики по которым мы размещаем товары
--
-- ===========================================================================
-- Навигация по процедуре. Копипастим название блока в поиск для перемещения.
-- ===========================================================================
--
-- Блок с созданием временных таблиц
-- Блок с созданием индексов
-- Блок заполнения профилей автозаказа
-- Блок заполнения приоритетов производителей
-- Блок заполнения поставщиков для заказа
-- Блок заполнения дублей
-- Блок заполнения товарами с рассчитанной потребностью для заказа
-- Блок заполнения настроек перемещения
-- Блок заполнения таблицы товаров с рассчитанной потребностью матричными товарами
-- Блок с заполнением #tmpPriceList предложениями к перемещению, заказу
-- Блок заполнения #tmpZakazParent "родительскими" данными
-- Блок проставления блокировки
-- Блок учета сроков годности используемых в размещении перемещений
-- Блок работы с маркетингами
-- Блок проставления макретинговой/матричной потребности
-- Блок размещения перемещений в заказе
-- Блок размещения товаров в заказе по предложениям поставщикиков из прайс-листа
-- Блок уменьшения лишних перемещений, когда итоговое кол-во заказа больше потребности
-- Блок ограничения заказа по сумме
-- Блок проставления у товара признака допустимости исключения из заказа - canBeExcluded
-- Блок проставления комментариев к анализируемым товарам
-- Блок заполнения дополнительных данных
-- Блок проставления комментариев к заказу
--
-- ===========================================================================
ALTER PROCEDURE [dbo].[KW_order_core_v13]
 @customerId int,				-- идентификатор контрагента
 @historId int,					-- идентификатор прайс-листа
 @docList dbo.IntList readonly, 		-- список документов для размещени.
 @block char(1),				-- Блокировка. 1 - учитывается, 0 - не учитывается.
 @double char(1),				-- Дубли. 1 - учитывается, 0 - не учитывается.
 @priority char(1),				-- Приоритет поставщиков. 1 - учитывается, 0 - не учитывается.  Сделано
 @donor char(1),				-- Доноры. 1 - учитывается, 0 - не учитывается.
 @srokG char(1),				-- Срок годности. 1 - учитывается, 0 - не учитывается.
 @matrix char(1),				-- Матрицы. 1 - учитывается, 0 - не учитывается.
 @parentDF_or_regId char(1),			-- делаем размещение по parentDrug и parentForm или regId. 1 - parentDrug и parentForm, 2 - regId.
 @reorder char(1),				-- Перезаказа. 1 - учитывается, 0 - не учитывается.
 @type_update char(1),				-- тип обновления. 1 - по поставщику, 2 - по минимальным ценам.
 @distr char(1),				-- Получать список поставщиков с приоритетами. 0 - нет, 1 - свой.
 @marketing char(1)				-- Учитывать маркетинговые товары. 0 - нет, 1 - да.
AS
BEGIN

 set nocount on;
 set transaction isolation level read uncommitted;

 declare
  @curDate datetime = getDate(),					-- текущая дата
  @regIdList dbo.IntList,						-- список товаров дял получения предложений из прайс-листа
  @parentCustomerId int = Miracle.dbo.GetParentCustomerId(@customerId), -- id владельца
  @defaultReserveDays int = 20,						-- дни товарного запаса, для расчета запаса на 20 дней.
  @moveDone int = 0,  							-- признак того, что размещение перемещений в заказ завершено. 0 - нет, 1 - да.
  @orderDone int = 0, 							-- признак того, что размещение товаров по предложениям поставщиков из прайса завершено. 0 - нет, 1 - да.
  @insertedRows int	  						-- кол-во добавленных в заказ товаров

  
 -- =============================================================================================
 -- Блок с созданием временных таблиц начало
 -- =============================================================================================

 -- таблица с настройками профилей автозаказа
 create table #tmpAutoZakazProfile (
  branchId int,		-- идентификатор филиала
  noMoveDaysMax int,	-- кол-во дней по профилю автозаказа, для учета товара неликвидным
  useRestriction bit,   -- использовать ограничение
  excludeDiscounted bit,-- ограничение по исключению уценки при расчете автозаказа
  AutoZakazProfileId int-- идентификатор используемого профиля автозаказа
 )

 --!todo nacenka = уценка, исправить
-- предложения поставщиков по товарам из прайс-листа
 create table #tmpPriceList (
  regId int,                 -- идентификатор товара
  drugId int,                -- идентификатор наименования
  formId int,                -- идентифкатор формы выпуска
  fabrId int,                -- идентификатор производителя
  sql2distrId int,           -- идентификатор поставщика (megapress)
  distrId int,               -- идентификатор поставщика
  donorBranchId int,         -- идентификатор филиала донора
  donorDataId int,           -- идентификатор записи строки автозаказа донора (нужен для join, альтернатива priceId)
  naklDataId int,            -- идентификатор строки накладной
  priceId bigint,            -- идентифкатор строки прайс-листа
  price numeric(15, 2),      -- цена
  qntOst int,                -- кол-во остатка
  minZakaz smallint,         -- минимальный заказ
  maxZakaz int,              -- максимальный заказ
  srokG date,                -- срок годности
  ratio smallint,            -- кратность
  distr varchar(150),        -- поставщик
  [block] char(1),           -- признак блокировки
  matrixTitleId int,         -- id таблицы
  minOst int,                -- минимальный остаток
  porogZakaz numeric(15, 5), -- Порог заказа
  priceFabr numeric(15, 2),  -- цена производителя
  nacenk char(2),	     -- обычно признак уценки
  ordered bit default 0      -- признак заказанной позиции
 )

 -- список родительских товаров дубля и суммарные характеристики, если дубля нет, то товар считается сам себе родительским и пишется сюда же
 create table #tmpZakazParent (
  parentRegId int,         -- родительский regId
  parentDrugId int,        -- родительский айди препарата
  parentFormId int,        -- родительский айди суммы
  parentDistrId int,       -- родительский поставщик
  branchId int,            -- филиал
  zakaz int,               -- кол-во к заказу (суммарное)
  zakazOrig int,           -- кол-во к заказу (суммарное исходное)
  speedMax numeric(15, 5), -- скорость уходимости (суммарная)
  threshold1 int,          -- количество товара на 20 дней торговли, нужно для расчёта картности (правая граница) (суммарное)
  threshold2 int,          -- количество товара в зависимоти от порога заказа, нужно для расчёта картности (левая граница) (суммарное)
  ost int,                 -- остаток (суммарный)
  tovInAWay int,           -- товар в пути (суммарный)
  complete bit default 0   -- признак завершенного размещения
 )

-- список дублей
 create table #tmpDouble (
  doubleId int,		  -- идентификатор строки дубля
  parentDoubleId int, 	  -- идентификатор родителя дубля, ссылка на строку выше т.е - doubleId
  drugId int,		  -- идентификатор наименования товара
  formId int		  -- идентификатор формы выпуска товара
 )

-- список перемещений
 create table #tmpMove (
  recepientBranchId int, -- филиал получатель
  donorBranchId int,	 -- филиал донор (отправитель)
  autoZakazTitleId int,	 -- идентификатор заголовка рассчитанной потребности
  isStorage char(1)      -- является ли филиал-донор складом
 )

-- список матричных товаров
 create table #tmpMatrixData (
  matrixTitleId int, 		-- идентификатор матрицы
  regId int,			-- идентификатор товара с учетом производителя
  drugId int,			-- идентификатор наименования товара
  formId int,			-- идентификатор форма выпуска товара
  branchId int,			-- идентификатор филиала
  minOst int,			-- минимальный остаток товара по плану матрицы
  porogZakaz numeric(15, 5),    -- порог заказа из настроек матрицы
  outOfAutoOrder bit default 0  -- признак матрицы исключения
 )

-- поставщики для матриц
 create table #tmpMatrixDistr (
  matrixTitleId int,	-- идентификатор матрицы
  branchId int,		-- идентификатор филиала
  distrId int		-- идентификатор поставщика
 )

 -- список товаров маркетинга АСНА из группы бездефектурное наличие (БДН)
 create table #tmpASNABDNProductList (
  branchId int,			 -- идентификатор филиала
  minQnt numeric(15, 5), 	 -- план штук
  regId int,			 -- идентификатор товара по производителю
  drugId int,			 -- идентификатор наименования товара
  formId int			 -- идентификатор формы выпуска товара
 )

 -- список товаров созвездия (из группы обязательная матрица)
 create table #tmpConstellationMatrixProductList (
  branchId int, -- идентификатор филиала
  regId int,	-- идентификатор товара по производителю
  drugId int,	-- идентификатор наименования товара
  formId int,	-- идентификатор формы выпуска товара
  minOst int	-- минимальный остаток по плану
 )

 -- список неликвидных товаров из созвездия (из группы обязательная матрица) с выполненым планом
 create table #tmpConstellationMatrixCompleteList (
  branchId int,		-- идентификатор филиала
  regId int,		-- идентификатор товара по производителю
  drugId int,		-- идентификатор наименования товара
  formId int,		-- идентификатор формы выпуска товара
  parentDrugId int, 	-- родительский идентификатор наименования товара 
  parentFormId int, 	-- родительский идентификатор формы выпуска
  qnt int		-- потребность товара в штуках
 )

 -- список предложений поставщиков по товарам из прайс-листа отсортированный в нужном для размещения в заказе порядке
 create table #tmpPriceListIdList (
  priceId bigint, -- идентификато предложения поставщика по товару
  pNumber int,	  -- порядковый номер при сортировке для размещения
  branchId int	  -- идентификатор филиала
 )

 -- поставщики для заказа
 create table #tmpDistr(
  distrId int,	  -- идентификатор поставщика в системе веб
  sql2DistrId int -- идентификатор поставщика в десктопе
 )

 -- приоритеты производителей
 create table #tmpFabrPriority (
  regId int,		-- идентификатор товара по производителю
  priority int,		-- приоритет производителя
  parentDrugId int, 	-- родительский идентификатор наименования товара
  parentFormId int	-- родительский идентификатор формы выпуска товара
 )

 -- приоритеты поставщиков маркетинговых товаров
 create table #tmpMarketingDistrPriority (
  [percent] numeric (15, 5), 	-- процент превышения минимальной цены, для игнора поставщика
  distrId int, 			-- идентификатор поставщика
  branchId int,			-- идентификатор филиала
  regId int,			-- идентификатор товара, т.к у каждого товара свои приоритеты
  [priority] int,		-- приоритет
  drugId int,			-- идентификатор наименования товара
  formId int,			-- идентификатор формы выпуска товара
  distrPrice numeric (15,5), 	-- стоимость предложения по рекомендованному поставщику
  minPrice numeric (15, 5)   	-- минимальная цена по товару
 )

 --!TODO проверить, скорректировать
 -- список дублей, для определения приоритетов производителей, затем отсюда добавляются в #tmpDoubles, если нужен учет дублей
 create table #tmpDoublesForPriority (
  id int default -1,	  	-- идентификатор
  parentId int default 0, 	-- родительский идентификатор, ссылка на строку выше т.е - id
  parentDrugId int,		-- родительский идентификатор наименования товара
  parentFormId int,		-- родительский идентификатор формы выпуска товара
  drugId int,			-- идентификатор наименования товара
  formId int			-- идентификатор формы выпуска товара
 )

 -- остаточные сроки годности по филиалам донорам
 create table #tmpDonorSrokG (
  branchId int,         -- идентификатор филиала
  srokGInDayForMove int -- остаточный срок годности в днях для перемещений
 )

 -- таблица товаров, у которых потребность по уходимости = 0, но теоритически потребность по матрицам/маркетингу есть
 create table #tmpGroupedMarketingMatrixNeedProducts (
  autoZakazDataId int, 	   -- идентификатор рассчитанной потребности товара
  branchId int,		   -- филиал
  drugId int,		   -- идентификатор наименования товара
  formId int,		   -- идентификатор формы выпуска товара
  parentDrugId int,	   -- родительский идентификатор наименования товара
  parentFormId int,	   -- родительский идентифиатор формы выпуска товара
  zakazOrig int		   -- новая потребность
 )

 -- =============================================================================================
 -- Блок с созданием временных таблиц закончен
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок с созданием индексов начало
 -- =============================================================================================

 -- Создём индексы
 create index Ind1 on #tmpPriceList (drugId, formId)
  include (minZakaz, srokG, ratio, [block], distrId, distr)

 create index Ind2 on #tmpPriceList (regId)
  include (minZakaz, srokG, ratio, [block], distrId, distr)

 create index Ind1 on #tmpDistrPriority (distrId, branchId)
  include ([priority])

 -- =============================================================================================
 -- Блок с созданием индексов закончен
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения профилей автозаказа начало
 -- =============================================================================================

 -- добавление филиалов в настройки профилей автозаказ
 insert into #tmpAutoZakazProfile (branchId)
 select branchId 
 from #tmpBranch with (nolock)

 -- прочие настройки, если есть не дефолтные
 update #tmpAutoZakazProfile set 
  noMoveDaysMax = azp2.noMoveDayCount, 
  useRestriction = azp2.useRestriction, 
  excludeDiscounted = isnull(azp2.excludeDiscounted, 0),
  AutoZakazProfileId = azp2.autoZakazProfileId
 from Miracle.dbo.AutoZakazProfileToBranch azptb with (nolock)
 left join Miracle.dbo.AutoZakazProfile azp2 with (nolock) 
 on azp2.autoZakazProfileId = azptb.autoZakazProfileId and 
    azp2.isDefault != '1' and 
    azp2.disable = '0'
 where azptb.branchId = #tmpAutoZakazProfile.branchId and azptb.disable = '0'

 -- иначе берем дефолтные
 update #tmpAutoZakazProfile set 
  noMoveDaysMax = azp.noMoveDayCount, 
  useRestriction = azp.useRestriction, 
  excludeDiscounted = isnull(azp.excludeDiscounted, 0),
  AutoZakazProfileId = azp.autoZakazProfileId
 from Miracle.dbo.AutoZakazProfile azp with (nolock)
 where azp.customerId = @customerId and azp.disable = '0' and azp.isDefault = '1' and noMoveDaysMax is null
 option (optimize for unknown)

 -- сохранение используемого профиля
 update #tmpBranch
 set AutoZakazProfileId = tp.AutoZakazProfileId
 from #tmpAutoZakazProfile tp
 where tp.branchId = #tmpBranch.branchId

 -- =============================================================================================
 -- Блок заполнения профилей автозаказа конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения приоритетов производителей начало
 -- =============================================================================================

 -- @important - Фактически, дубли заполняются здесь, но их использование зависит от параметра.

 -- собираем дубли
 insert into #tmpDoublesForPriority(id, parentId, drugId, formId, parentDrugId, parentFormId)
 select dc.DoubleCustomerId, dc.ParentDoubleCustomerId, dc.drugId, dc.formId, isnull(dc2.DrugId, dd.DrugId), isnull(dc2.FormId, dd.FormId)
 from Miracle.dbo.DoubleCustomer dc
 left join Miracle.dbo.DoubleCustomer dc2 on dc.[ParentDoubleCustomerId] = dc2.DoubleCustomerId and dc2.Disable = '0'
 left join Miracle.dbo.DoubleDefault dd on dd.DoubleDefaultId = dc.DoubleDefaultId
 where dc.parentCustomerId = @parentCustomerId and dc.[disable] = '0' and isnull(dd.[disable], '0') = '0'

 -- сбрасываем у родителей идентификар на 0, для совместимости дальнейшего кода TODO поправить этот момент
 update tdfp
 set parentId = 0
 from #tmpDoublesForPriority tdfp
 where drugId = parentDrugId and formId = parentFormId

-- добавление в список приоритетов товаров, у которых нет дубля
 insert into #tmpFabrPriority(regId, priority, parentDrugId, parentFormId)
 select vr.regid, ap.priority, ap.drugId, ap.formId
 from AutoZakazFabrPriority ap with (nolock)
 join Megapress.dbo.Registry vr with (nolock) on ap.drugId = vr.drugid and ap.formId = vr.formid and ap.fabrId = vr.fabrId
 where not exists (select 1 from #tmpDoublesForPriority tdp where tdp.parentDrugId = ap.drugId and tdp.parentFormId = ap.formId)
  and ap.usingInAutoZakaz = '1' and parentCustomerId = @parentCustomerId

-- добавление в список приоритетов дублей
 insert into #tmpFabrPriority(regId, priority, parentDrugId, parentFormId)
 select vr.regid, afp.priority, tdp.parentDrugId, tdp.parentFormId
 from #tmpDoublesForPriority tdp with (nolock)
 left join AutoZakazFabrPriority afp with (nolock) 
 on tdp.parentDrugId = afp.drugId and tdp.parentFormId = afp.formId and afp.usingInAutoZakaz = '1' and afp.parentCustomerId = @parentCustomerId
 join Megapress.dbo.Registry vr with (nolock) on vr.drugid = tdp.drugid and vr.formid = tdp.formId and vr.fabrid = afp.fabrid

-- определение приоритета
 update #tmpFabrPriority
 set priority = f.max_priority
 from (
  select isnull(max(nullif(priority, 0)), 0) + 1 as max_priority, parentDrugId, parentFormId
  from #tmpFabrPriority with (nolock)
  group by parentDrugId, parentFormId
 ) f
 where #tmpFabrPriority.parentDrugId = f.parentDrugId and #tmpFabrPriority.parentFormId = f.parentFormId
  and nullif(#tmpFabrPriority.priority, 0) is null

 -- =============================================================================================
 -- Блок заполнения приоритетов производителей конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения поставщиков для заказа начало
 -- =============================================================================================

 -- если перезаказ по актуальному прайс-листу, но не расформирование, список поставщиков уже заполнен
 -- заполняем #tmpDistr т.к из него заполняются предложения поставщиков из прайс-листа к заказу
 if @type_update != '0' and exists (select 1 from #tmpDistrPriority)
 insert into #tmpDistr(distrId, sql2DistrId)
 select tdp.distrId, co.SQL2DistrID
 from #tmpDistrPriority tdp
 join Miracle.dbo._CustomerID_OrgID co with (nolock) on co.CustomerID = tdp.distrId

 -- Приоритеты поставщиков (если @distr = '0' то эта таблица должна быть заполнена ранее)
 if @distr = '1'
  begin
   -- заполнение списка поставщиков (#tmpDistr)
   exec Miracle.dbo.KW_GetCustomerDistrs_v1 @customerId, @historId

   insert into #tmpDistrPriority (
    branchId, distrId, [priority]
   )
   select b.BranchID, d.distrId distr_id, case when @priority = '1' then isnull(cast(bd.cof as numeric), 1.0) else 1.0 end [priority]
   from #tmpDistr d with (nolock)
   left join #tmpBranch b with (nolock) on 1 = 1
   left join Miracle.dbo.BranchDistr bd with (nolock) on bd.DistrID = d.distrId and bd.BranchID = b.branchId and bd.CustomerID = @customerId
   where isnull(bd.selected, '0') = '1'
   group by b.BranchID, d.distrId, bd.cof
   option (optimize for unknown)
  end

 -- =============================================================================================
 -- Блок заполнения поставщиков для заказа конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения дублей начало
 -- =============================================================================================

 -- @important дубли заполняются выше, но используются в зависимости от параметра
 -- @important см. Блок заполнения приоритетов производителей

 -- Дубли
 if @double = '1'
  begin
   insert into #tmpDouble(doubleId, parentDoubleId, drugId, formId)
   select id, parentId, drugId, formid 
   from #tmpDoublesForPriority with (nolock)
  end

 -- =============================================================================================
 -- Блок заполнения дублей конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения товарами с рассчитанной потребностью для заказа начало
 -- =============================================================================================

 -- если потребность уже заполнена, то это перезаказ старого заказа - идем дальше, иначе это создание обычного автозаказа - заполняем
 if not exists(select 1 from #tmpZakaz)
 begin
 insert into #tmpZakaz(
	autoZakazDataId, branchId, drugId, formId, zakaz, zakazOrig, ost, tovInAWay, threshold1, threshold2, speedMax, kEff, noMoveDay
 )
 select zd.autoZakazDataId,
		zt.branchId,
		zd.drugId,
		zd.formId,
		isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix),
		isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix),
		zd.ost,
		zd.tovInAWay,
		zd.speedMax,
		round(zd.speedMax * @defaultReserveDays, 0),
		zd.speedMax,
		zd.kEff,
		isnull(zd.noMoveDay, 0)
 from Miracle.dbo.AutoZakazTitle zt with (nolock)
 join Miracle.dbo.AutoZakazData zd with (nolock) on zt.autoZakazTitleId = zd.autoZakazTitleId
 where (
	isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix) > 0 or 
	exists (select 1 from #tmpDouble td with (nolock) where td.drugId = zd.drugId and td.formId = zd.formId)	
  ) and not exists (
    select 1
    from Miracle.dbo.AutoZakazNoAssort na with (nolock)
    where na.branchId = zt.branchId and na.drugId = zd.drugId and na.formId = zd.formId and na.[disable] = '0'
    ) and zd.autoZakazTitleId in (select value from @docList)
 option (optimize for unknown)
 end

 -- проставляем родительский товар (название, форма), если нет дублей или это родительский товар, то parentId = Id
 update tz
 set parentDrugId = iif(tdp.drugId is null, tz.drugId, tdp.drugId), parentFormId = iif(tdp.formId is null, tz.formId, tdp.formId)
 from #tmpZakaz tz with (nolock)
 left join #tmpDouble td with (nolock) on td.drugId = tz.drugId and td.formId = tz.formId and td.parentDoubleId != 0
 left join #tmpDouble tdp with (nolock) on tdp.doubleId = td.parentDoubleId

  -- применяем всем дочерним дублям, показатели рассчитанные для род. дубля, как для одного товара
 update tz
 set zakaz = oa.zakaz, zakazOrig = oa.zakazOrig, speedMax = oa.speedMax, threshold1 = oa.threshold1, threshold2 = oa.threshold2,
  ost = oa.ost, tovInAWay = oa.tovInAWay, noMoveDay = oa.noMoveDay
 from #tmpZakaz tz with (nolock)
 outer apply (
  select tz2.zakaz, tz2.zakazOrig, tz2.speedMax, tz2.threshold1, tz2.threshold2, tz2.ost, tz2.tovInAWay, tz2.noMoveDay
  from #tmpZakaz tz2 with (nolock)
  where tz2.parentDrugId = tz2.drugId and tz2.parentFormId = tz2.formId and tz2.parentDrugId = tz.parentDrugId
   and tz2.parentFormId = tz.parentFormId and tz2.branchId = tz.branchId
 ) oa
 where exists (select 1 from #tmpDouble td with (nolock) where tz.parentDrugId = td.drugId and tz.parentFormId = td.formId)
 -- =============================================================================================
 -- Блок заполнения товарами с рассчитанной потребностью для заказа конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения настроек перемещения начало
 -- =============================================================================================

 if @donor = '1'
  begin
   -- получаем связку реципиентов и доноров
   insert into #tmpMove (recepientBranchId, donorBranchId, autoZakazTitleId)
   select tb.branchId, amd.branchId, oa.autoZakazTitleId
   from #tmpBranch tb with (nolock)
   join Miracle.dbo.AutoZakazMoveSettings ams with (nolock) on tb.branchId = ams.branchId
   join Miracle.dbo.AutoZakazMoveDonor amd with (nolock)
   on amd.autoZakazMoveSettingsId = ams.autoZakazMoveSettingsId and amd.[disable] = '0'
   outer apply (
    select top 1 azt.autoZakazTitleId
    from Miracle.dbo.AutoZakazTitle azt with (nolock)
    where azt.createDate >= DATEADD(d, -1, cast(@curDate as date)) and amd.branchId = azt.branchId
    order by azt.createDate desc
   ) oa
   where isnull(ams.[select], 0) = 1

   -- обновляем состояние чекбокса 'Склад' по каждому филиалу из таблицы AutoZakazMoveSettings
   update tmp
   set tmp.isStorage = isnull(ams.isStorage, '0')
   from #tmpMove tmp
   left join Miracle.dbo.AutoZakazMoveSettings ams on tmp.donorBranchId = ams.branchId

   update tmp
   set tmp.isStorage = '0'
   from #tmpMove tmp
   where tmp.isStorage is null
  end

 -- =============================================================================================
 -- Блок заполнения настроек перемещения конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения таблицы товаров с рассчитанной потребностью матричными товарами начало
 -- =============================================================================================

 -- todo проверить все внимательнее, много обращений в dbo.Registry
 if @matrix = '1'
  begin

  declare
  @parentCustomerTime datetime, -- текущие дата и время владельца
  @parentCustomerDate date	-- текущая дата владельца

  --таблица с матрицами филиалами и категориями
  create table #tmpMatrixTitle (
   matrixTitleId int,	-- идентификатор матрицы
   branchId int,	-- идентификатор филиала
   [priority] smallint, -- приоритет матрицы
   createDate datetime, -- дата создания матрицы
   outOfAutoOrder bit   -- признак того, что это матрица исключения 0 - нет, 1 - да
  )

  -- таблица всех товаров в матрицах
  create table #tmpAllMatrixData (
   matrixTitleId int,		  -- идентификатор матрицы
   matrixDataId int,		  -- идентификатор строки товара
   branchId int,		  -- идентификатор филиала
   topRegId int,		  -- идентификатор товара привязанный в качестве родителя
   drugId int,			  -- идентификатор наименования товара
   formId int,			  -- идентификатор формы выпуска товара
   fabrType char(1),		  -- тип учета товара 0 - без производителя, 1 - по приоритету производителя, 2 - по конкретному производителю
   minOst int,			  -- минимальный остаток товара
   porogZakaz numeric(15, 5), 	  -- порог заказа (наверное, минимальное кол-во заказа)
   [priority] smallint,		  -- приоритет матрицы
   createDate datetime,		  -- дата создания матрицы
   outOfAutoOrder bit		  -- признак того, что это матрица исключения 0 - нет, 1 - да
  )

  -------------------------------------------------------------------------------
  -- получения списка матриц
  -------------------------------------------------------------------------------

  -- получаем текущие дата и время владельца
  select @parentCustomerTime = todatetimeoffset(@curDate, coalesce(ci.timeZone, '+03:00'))
  from Miracle.dbo.Customer cu with (nolock)
  left join Miracle.dbo.City ci with (nolock) on ci.CityID = cu.CityID
  where cu.CustomerID = @parentCustomerId

  -- выделяем только дату от даты и времени владельца
  select @parentCustomerDate = convert(date, @parentCustomerTime)

  -- список матриц
  insert into #tmpMatrixTitle (matrixTitleId, branchId, [priority], createDate, outOfAutoOrder)
  select mt.matrixTitleId, tb.branchId, mt.[priority], mt.createDate, isnull(mt.outOfAutoOrder, 0)
  from  #tmpBranch tb with (nolock)
  join Miracle.dbo.MatrixInBranch mb with (nolock) on mb.branchId = tb.branchId and mb.[disable] = '0'
  join Miracle.dbo.MatrixTitle mt with (nolock) on mb.matrixTitleId = mt.matrixTitleId
  where mt.[disable] = '0' and isnull(mt.dateEnd, dateadd(year, 100, @parentCustomerDate)) >= @parentCustomerDate and 
	mt.parentCustomerId = @customerId and mt.isOrders = '1' and mt.dateBegin <= @parentCustomerDate 

  -------------------------------------------------------------------------------
  -- получения списка товаров по матрицам
  -------------------------------------------------------------------------------
  
   -- все матричные товары 
   insert into #tmpAllMatrixData (
    matrixDataId, matrixTitleId, fabrType, topRegId, drugId, formId, branchId, minOst, porogZakaz, [priority], createDate, outOfAutoOrder
   )
   select md.matrixDataId,
    mtb.matrixTitleId,
    md.fabrType,
    md.topRegId,
    r.DRUGID,
    r.FORMID,
    mtb.branchId,
    isnull(nullif(isnull(mdc.minOst, md.minOst), 0), 1),
    isnull(mdc.porogZakaz, isnull(md.porogZakaz, 1)),
    mtb.[priority],
    mtb.createDate,
    mtb.outOfAutoOrder
   from #tmpMatrixTitle mtb with (nolock)
   join Miracle.dbo.MatrixData md with (nolock) on mtb.matrixTitleId = md.matrixTitleId and md.[disable] = '0'
   join Megapress.dbo.REGISTRY r with (nolock) on r.regId = md.topRegId and r.FLAG = '0'
   left join Miracle.dbo.MatrixDataCategory mdc with (nolock)
   on mdc.matrixDataId = md.MatrixDataId and mdc.matrixCategoryId = '0'

  -------------------------------------------------------------------------------
  -- получения списка поставщиков для матриц
  -------------------------------------------------------------------------------

   -- поставщики для матриц
   insert into #tmpMatrixDistr(matrixTitleId, branchId, distrId)
   select mb.matrixTitleId, mb.branchId, md.distrId
   from #tmpMatrixTitle mb with (nolock)
   left join Miracle.dbo.MatrixDistrib md with (nolock) on mb.matrixTitleId = md.matrixTitleId and md.checkDistrib = '1'

  --------------------------------------------------------------------------------
  -- сбор информации по матричным товарам использующихся глобально начало
  -- =============================================================================

   /*
   сбрасываем matrixDataId тех товаров, у которых не надо брать доп. информацию по товарам, на случай, если будет несколько одинаковых товаров,
   оставляя возможность проверить на матрицу исключения
   */
   update tmd
   set matrixDataId  = null
   from #tmpAllMatrixData tmd
   outer apply (
    select min(tmd2.[priority]) as [priority] -- если вдруг есть товары с таким же drug+form - берем наименьший приоритет
    from #tmpAllMatrixData tmd2
    where tmd2.drugId = tmd.drugId and tmd2.formId = tmd.formId and tmd2.branchId = tmd.branchId
   ) oa
   outer apply (
	select max(tmd2.createDate) as [date] -- определяем позднее созданную матрицу по наименьшему приоритету, если вдруг приоритет одинаковый
	from #tmpAllMatrixData tmd2
	where tmd2.drugId = tmd.drugId and tmd2.formId = tmd.formId and tmd2.branchId = tmd.branchId and tmd2.priority = oa.priority
   ) oa2
   where tmd.createDate != oa2.[date]

   -- сбор позиций без учета производителя
   insert into #tmpMatrixData (matrixTitleId, regId, drugId, formId, branchId, minOst, porogZakaz)
   select tmd.matrixTitleId, r.REGID, r.DRUGID, r.FORMID, tmd.branchId, tmd.minOst, tmd.porogZakaz
   from #tmpAllMatrixData tmd with (nolock)
   join Megapress.dbo.REGISTRY r with (nolock) on r.DRUGID = tmd.drugId and r.FORMID = tmd.formId and r.FLAG = '0'
   where tmd.fabrType = '0' and tmd.matrixDataId is not null

   -- позиции с учетом приоритета производителя у которых приоритет больше нуля.
   insert into #tmpMatrixData (matrixTitleId, regId, drugId, formId, branchId, minOst, porogZakaz)
   select tmd.matrixTitleId, r.REGID, r.DRUGID, r.FORMID, tmd.branchId, tmd.minOst, tmd.porogZakaz
   from #tmpAllMatrixData tmd with (nolock)
   join Miracle.dbo.MatrixFabrPriority mf with (nolock, forceseek) on mf.matrixDataId = tmd.matrixDataId
   join Megapress.dbo.REGISTRY r with (nolock) on r.DRUGID = tmd.drugId and r.FORMID = tmd.formId and r.FABRID = mf.fabrId and r.FLAG = '0'
   where tmd.fabrType = '1' and mf.fabrPriority > 0 and tmd.matrixDataId is not null
   and not exists (select 1 from #tmpMatrixData tu where r.REGID = tu.regId and tmd.branchId = tu.branchId)

   -- позиции с учетом конкретного производителя.
   insert into #tmpMatrixData (matrixTitleId, regId, drugId, formId, branchId, minOst, porogZakaz)
   select tmd.matrixTitleId, tmd.topRegId, tmd.DRUGID, tmd.FORMID, tmd.branchId, tmd.minOst, tmd.porogZakaz
   from #tmpAllMatrixData tmd with (nolock)
   where tmd.fabrType = '2' and tmd.matrixDataId is not null
   and not exists (select 1 from #tmpMatrixData tu where tmd.topRegId = tu.regId and tmd.branchId = tu.branchId)

   -- признак матрицы исключения у товара
   update tu
   set outOfAutoOrder = 1
   from #tmpMatrixData tu
   where exists (
	select 1 
	from #tmpAllMatrixData tmd 
	where tmd.branchId = tu.branchId and tmd.drugId = tu.drugId and tmd.formId = tu.formId and tmd.outOfAutoOrder = 1
   )

  -- =============================================================================
  -- сбор информации по матричным товарам использующихся глобально конец
  --------------------------------------------------------------------------------

   /*
   ----------------------------------------------------------------------------------
   -- добавление матричных товаров в анализируемую таблицу с товарами с потребностью
   ----------------------------------------------------------------------------------

   -- добавление недостающих матричных товаров
   insert into #tmpZakaz(autoZakazDataId, branchId, drugId, formId, zakaz, zakazOrig, ost, tovInAWay, threshold1, threshold2, speedMax, kEff)
   select zd.autoZakazDataId,
    	  zt.branchId,
    	  zd.drugId,
    	  zd.formId,
    	  isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix),
    	  isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix),
    	  zd.ost,
    	  zd.tovInAWay,
    	  zd.speedMax,
    	  round(zd.speedMax * @defaultReserveDays, 0),
    	  zd.speedMax,
    	  zd.kEff--oa.autoZakazTitleId, a.drugId, a.formId
    -- todo не попадает товар, которого нету в autozakazdata, если так быть не должно смотреть сюда
   from #tmpMatrixData a
   left join Miracle.dbo.AutoZakazData zd with (nolock) on zd.drugId = a.drugId
    and zd.formId = a.formid and zd.autoZakazTitleId in (select value from @docList)
   left join Miracle.dbo.AutoZakazTitle zt with (nolock)
   on zt.autoZakazTitleId = zd.autoZakazTitleId
   where isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix) > 0 and not exists (
    select 1
    from #tmpZakaz tz with (nolock)
    where a.drugId = tz.drugId and a.formId = tz.formId and a.branchId = tz.branchId
    )
   option (optimize for unknown)

  ----------------------------------------------------------------------------------
  -- обновление информации по "родителю"
  ----------------------------------------------------------------------------------
  -- todo проверить, скорректировать
  update tz
  set parentDrugId = c.parentdrugId, parentFormId = c.parentformId
  from #tmpZakaz tz
  outer apply (
   select tz2.drugId, tz2.formId, isnull(tdp2.drugId, tz.drugid) as parentDrugId, isnull(tdp2.formId, tz.formId) as parentFormId
   from #tmpZakaz tz2 with (nolock)
   left join #tmpDouble tdp with (nolock) on tz2.drugId = tdp.drugId and tz2.formId = tdp.formId
   left join #tmpDouble tdp2 with (nolock) on tdp2.doubleId = tdp.parentDoubleId
   where tz2.drugid = tz.drugId and tz2.formId = tz.formId
  ) c
  where tz.parentDrugId is null and tz.parentFormId is null and tz.drugId = c.drugId and tz.formId = tz.formId
  */

  drop table #tmpAllMatrixData
  drop table #tmpMatrixTitle
end

 -- =============================================================================================
 -- Блок заполнения таблицы товаров с рассчитанной потребностью матричными товарами конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок с заполнением #tmpPriceList предложениями к перемещению, заказу начало
 -- =============================================================================================

 ----------------------------------------------------------------------------------
 -- собираем товары для получения прайса
 ----------------------------------------------------------------------------------

 -- !TODO проверить целесообразность проверки по flag через Registry, если такая проверка уже имеется в расчете потребности.
 -- добавление дублей в список товаров для получения предложений прайс-листа
 insert into @regIdList ([value])
 select r.REGID
 from #tmpDouble td with (nolock)
 join Megapress.dbo.Registry r with (nolock) on r.DRUGID = td.drugId and r.FORMID = td.formId and r.FLAG = '0'
 where not exists (select 1 from #tmpZakaz tz with (nolock) where tz.drugId = td.drugId and tz.formId = td.formId)
 group by r.REGID

 -- добавление остальных товаров в список для получения предложений прайс-листа
 insert into @regIdList ([value])
 select r.REGID
 from #tmpZakaz tz with (nolock)
 join Megapress.dbo.Registry r with (nolock) on r.DRUGID = tz.drugId and r.FORMID = tz.formId and r.FLAG = '0'
 where not exists (select 1 from @regIdList rl where rl.value = r.REGID)
 group by r.REGID

 ----------------------------------------------------------------------------------
 -- заполнение предложений доноров
 ----------------------------------------------------------------------------------

 if @donor = '1' 
 begin
   -- получаем предложения аптек доноров, которые не являются складами, по последнему рассчитанному автозаказу
   insert
    into #tmpPriceList (
    regId, drugId, formId, fabrId, donorBranchId, donorDataId, price, qntOst, naklDataId, minZakaz, maxZakaz, srokG,
    ratio, [block], priceFabr
   )
   select r.REGID,
    azd.drugId,
    azd.formId,
    r.FABRID,
    tm.donorBranchId,
    azd.autoZakazDataId,
    0.0,
    cast(nd.uQntOst as int),
    nd.naklDataId,
    1,
    azd.excess,
    isnull(nd.SrokG, nd2.SrokG),
    1,
    '0',
    null
   from (
    select m.donorBranchId
	  ,autoZakazTitleId
	  ,isStorage
    from #tmpMove m
    group by m.donorBranchId
	    ,autoZakazTitleId
	    ,isStorage
   ) tm
   join Miracle.dbo.AutoZakazData azd with (nolock)
   on azd.autoZakazTitleId = tm.autoZakazTitleId and isnull(azd.excess, 0) > 0 and tm.isStorage != '1'
   join Megapress.dbo.Registry r with (nolock) on r.DRUGID = azd.drugId and r.FORMID = azd.formId
   join Miracle.dbo.NaklData nd with (nolock)
   on nd.branchId = tm.donorBranchId and nd.[disable] = '0' and nd.uQntOst > 0.001 and nd.RegID = r.REGID
   left join Miracle.dbo.NaklData nd2 with (nolock) on nd.FirstNaklDataID = nd2.NaklDataID

  -- TODO объединить в 1 запрос

  -- заполняем предложения к перемещению от аптек складов
  insert into #tmpPriceList (
    regId, drugId, formId, fabrId, donorBranchId, donorDataId, price, qntOst, naklDataId, minZakaz, maxZakaz, srokG,
    ratio, [block], priceFabr
  )
  select r.REGID,
  r.drugId,
  r.formId,
  r.FABRID,
  tm.donorBranchId,
  null, -- ?
  0.0,
  cast(nd.uQntOst as int),
  nd.naklDataId,
  1,
  nd.uQntOst, -- кладём весь остаток товаров из склада
  isnull(nd.SrokG, nd2.SrokG),
  1,
  '0',
  null
  from (
    select m.donorBranchId
	  ,autoZakazTitleId
	  ,isStorage
    from #tmpMove m
    group by m.donorBranchId
	    ,autoZakazTitleId
	    ,isStorage
   ) tm
  join Miracle.dbo.NaklData nd with (nolock)
  on nd.branchId = tm.donorBranchId and nd.[disable] = '0' and nd.uQntOst > 0.001 and tm.isStorage = '1'
  join Megapress.dbo.Registry r with (nolock) on nd.RegID = r.REGID
  left join Miracle.dbo.NaklData nd2 with (nolock) on nd.FirstNaklDataID = nd2.NaklDataID
 end

 ----------------------------------------------------------------------------------
 -- заполнение предложений из прайс-листа
 ----------------------------------------------------------------------------------

 -- Получаем предложния поставщиков из прайс-листа по анализируемым товарам
 insert into #tmpPriceList(
  regId, drugId, formId, fabrId, distrId, sql2DistrId, priceId, price, qntOst, minZakaz, srokG, ratio, distr, priceFabr, nacenk
 )
 exec Miracle.dbo.AutoZakazGetSvodPriceByRegId_v5 @customerId, @historId, @regIdList

 -- обновление сводного прайс листа для Матричных товаров. Мин остаток, порог заказа.
 update tp
 set tp.matrixTitleId = ur.matrixTitleId, tp.minOst = ur.minOst, tp.porogZakaz = ur.porogZakaz
 from #tmpPriceList tp with (nolock)
 join #tmpMatrixData ur with (nolock) on tp.regId = ur.regId

 -- =============================================================================================
 -- Блок с заполнением #tmpPriceList предложениями к перемещению, заказу конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения #tmpZakazParent "родительскими" данными начало
 -- =============================================================================================

  -- для родительских позиций по дублям добавляем показатели на основе которых будет происходить размещение
 -- (больше не суммируем, все данные для дубля считаются в расчетах потребности)
 insert into #tmpZakazParent (
	parentDrugId, parentFormId, zakazOrig, zakaz, speedMax, threshold1, threshold2, ost, tovInAWay, branchId
 )
 select tz.parentDrugId,
	tz.parentFormId,
	tz.zakaz,
	tz.zakaz,
	tz.speedMax,
	tz.threshold1,
	tz.threshold2,
	tz.ost,
	tz.tovInAWay,
	tz.branchId
 from #tmpZakaz tz with (nolock)
 where tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId

 -- =============================================================================================
 -- Блок заполнения #tmpZakazParent "родительскими" данными конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок проставления блокировки начало
 -- =============================================================================================

-- получаем признак инверсии списка болокировки
 declare @inversion char(1) = Miracle.dbo.KW_GetBlockZakInversion_v2(@parentCustomerId)

-- проставляем блокировку
 if @block = '1' and @inversion is not null
  begin

   update tp
   set tp.[block] = case when (@inversion = '1' and isnull(isnull(bz.[disable], bzf.[disable]), '1') = '1'
    or @inversion = '0' and isnull(isnull(bz.[disable], bzf.[disable]), '1') = '0') and isnull(bze.[disable], '1') = '1'
    then '1'
    else '0' end
   from #tmpPriceList tp with (nolock)
   left join Miracle.dbo.KW_BlockZak bzf with (nolock) on bzf.fabrId = tp.fabrId and bzf.parentId = @parentCustomerId
   left join Miracle.dbo.KW_BlockZak bz with (nolock)
   on bz.RegId = tp.regId and bz.parentId = @parentCustomerId
    --left join Miracle.dbo.KW_BlockZakExc bze on bze.KW_BlockZakId = bz.KW_BlockZakId and bze.distrId = tp.distrId
   left join Miracle.dbo.KW_BlockZakExc bze with (nolock)
   on bze.KW_BlockZakId = isnull(bz.KW_BlockZakId, bzf.KW_BlockZakId) and bze.distrId = tp.distrId
   option (optimize for unknown)

   update tp
   set tp.[block] = '0'
   from #tmpPriceList tp
   where tp.[block] is null

  end
 else
  -- Иначе проставляем нулями
  update #tmpPriceList
  set [block] = '0'

 -- =============================================================================================
 -- Блок проставления блокировки конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок учета сроков годности используемых в размещении перемещений начало
 -- =============================================================================================

 -- todo думаю, нужны корректировки по профилю автозаказа
-- Получение срока годности
 if @srokG = '1'
  begin

   declare
   @defSrokGInMonth smallint = 6,  -- остаточный срок годности в месяцах по умолчанию
   @defSrokGInDays smallint = 180 -- остаточный срок годности в днях по умолчанию

   -- получаем настройку по остаточным срокам годности
   insert into #tmpSrokG(
    branchId, srokGInMonth
   )
   select tb.branchId, isnull(azp.srokGInMonth, @defSrokGInMonth)
   from #tmpBranch tb with (nolock)
   join Miracle.dbo.AutoZakazProfile azp with (nolock) on azp.autoZakazProfileId = tb.autoZakazProfileId

   insert into #tmpDonorSrokG(
    branchId, srokGInDayForMove
   )
   select amsd.branchId,
    isnull(amsd.maxDaySrokG, @defSrokGInDays)
   from #tmpBranch tb with (nolock)
   left join Miracle.dbo.AutoZakazMoveSettings ams with (nolock) on ams.branchId = tb.branchId
   left join Miracle.dbo.AutoZakazMoveDonor amd with (nolock)
   on amd.autoZakazMoveSettingsId = ams.autoZakazMoveSettingsId and amd.disable = '0'
   left join Miracle.dbo.AutoZakazMoveSettings amsd with (nolock) on amsd.branchId = amd.branchId
   group by amsd.branchId, isnull(amsd.maxDaySrokG, @defSrokGInDays)
  end

 -- =============================================================================================
 -- Блок учета сроков годности используемых в размещении перемещений конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок работы с маркетингами начало
 -- =============================================================================================

 if @marketing = '1'
  begin

  -- regids анализируемых товаров
  create table #tmpZakazRegIds (
     drugId int -- идентификатор наименования
    ,formId int -- идентификатор формы
    ,regId  int -- идентификатор с привязкой по производителю
  )
  
  -- проценты превышения для игнора поставщика по филиалам
  create table #tmpMarketingIgnorePercent (
   branchId int,		-- филиал
   [percent] numeric (15, 5)	-- процент превышения
  )

  -- cписок всех товаров созвездения без учета их типа
  create table #tmpAllConstellationProductList (
   branchId int,
   regId int,
   drugId int,
   formId int,
   minOst int,
   constellationType varchar(20),
   productId int,
   actionId int
  )

  -- список товаров всех маркетинговых групп
  create table #tmpAllMarketingGroupsProductList (
   branchId int,		  -- идентификатор филиала
   minQnt numeric(15, 5), 	  -- план штук
   regId int,			  -- идентификатор товара по производиетлю в вебе
   drugId int,			  -- идентификатор наименования товара в вебе
   formId int,			  -- идентификатор формы выпуска в вебе
   nnt int,			  -- идентификатор товара в маркетинговой системе
   typeCode int,		  -- код маркетинговой программы АСНА
   [required] bit,		  -- 1 - обязательное бездефектурное наличие, 0 - рекомендуемое бездефектурное наличие (АСНА)
   marketingType smallint 	  -- тип маркетинга, 1 - созвездие, 2 - АСНА
  )

   -- необходимая категория асна
   declare @typeId int = 9
   -- созвездие (обязательная матрица)
   declare @constellationType varchar(20) = 'MANDATORY_MATRIX'
   -- код региона
   declare @regionCode int

   -- получаем код региона
   select @regionCode = substring(INN, 1, 2)
   from Miracle.dbo.Customer c with(nolock)
   where c.CustomerID = @customerId
   option(optimize for unknown)

   ------------------------------------------------------------------------------------------------------------

   -- получаем regid анализируемых товаров
   insert into #tmpZakazRegIds(
	 regId
	,drugId
	,formId
   )
   select r.REGID
	 ,r.DRUGID
	 ,r.FORMID
   from (
    select t.drugid
	  ,t.formId
    from #tmpZakaz t
    group by t.drugId
	    ,t.formId
   ) tz
   join Megapress.dbo.REGISTRY r on r.DRUGID = tz.drugId and r.FORMID = tz.formId and r.FLAG = '0'

   ------------------------------------------------------------------------------------------------------------
   -- Созвездие
   ------------------------------------------------------------------------------------------------------------

   -- заполнение всех товаров созвездия без учета их типов, которые есть в #tmpZakazRegIds
   insert into #tmpAllConstellationProductList (branchId, regId, drugId, formId, minOst, constellationType, productId, actionId)
   select co.branchId, vr.regId, vr.drugId, vr.formId, max(cp.quantity), ca.marketing_action_type, cn.product_id, cp.marketing_action_id
   from Miracle.dbo.ConstellationOptions co with (nolock)
   join #tmpBranch bmd with (nolock) on bmd.branchId = co.branchId
   join Miracle.dbo.ConstellationBranch cb with (nolock) on cb.map_pharmacy_id = co.branchId and cb.Disable = '0'
   join Miracle.dbo.ConstellationMarketingAction ca with (nolock) on ca.marketing_action_id = cb.marketing_action_id and ca.[Disable] = '0'
    and ca.[state] = 0 and @curDate between ca.date_start and ca.date_end
   join Miracle.dbo.ConstellationProducts cp with (nolock) on cp.marketing_action_id = ca.marketing_action_id and cp.[Disable] = '0'
   join Miracle.dbo.ConstellationNomenclature cn with (nolock) 
   on cn.product_id = cp.product_id and cn.[Disable] = '0' and cn.map_nomenclature_code != 0
   join #tmpZakazRegIds vr with (nolock) on vr.regId = cn.map_nomenclature_code
   where case when ca.marketing_action_type = 'MANDATORY_MATRIX' then isnull(co.HighlightNeedMatrixSvodPrice, '0')
	      when ca.marketing_action_type = 'RECOMMENDED_GOODS' then isnull(co.HighlightRecomendMatrixSvodP, '0')
	      when ca.marketing_action_type = 'PROCUREMENT' then isnull(co.HighlightPurchaseSvodPrice, '0')
	      when ca.marketing_action_type = 'PRODUCT_OF_THE_DAY' then isnull(co.HighlightProductDaySvodPrice, '0')
	      when ca.marketing_action_type = 'PRIVATE_LABEL' then isnull(co.HighlightUSTMSvodPrice, '0') end = '1'
   group by co.branchId, vr.regId, vr.drugid, vr.formid, ca.marketing_action_type, cn.product_id, cp.marketing_action_id

   -- заполнение товаров созвездия по обязательной матрице MANDATORY_MATRIX
   insert into #tmpConstellationMatrixProductList (branchId, regid, drugId, formId, minOst)
   select tAMPL.branchId, tAMPL.regId, tAMPL.drugId, tAMPL.formId, tAMPL.minOst 
   from #tmpAllConstellationProductList tAMPL with (nolock)
   where tAMPL.constellationType = @constellationType

  --собираем неликвидные товары из созвездия по обязательной матрице MANDATORY_MATRIX с выполненым планом
   insert into #tmpConstellationMatrixCompleteList (branchId, regid, drugId, formId, parentDrugId, parentFormId, qnt)
   select tz.branchId, tc.regId, tz.drugId, tz.formId, tz.parentDrugId, tz.parentFormId, tz.zakaz
   from #tmpConstellationMatrixProductList tc
   join #tmpZakaz tz with (nolock) on tc.branchId = tz.branchId and tc.drugId = tz.drugId and tc.formId = tz.formId and 
				      tz.ost + tz.tovInAWay >= isnull(tc.minOst, 0) and tz.zakazOrig < isnull(tc.minOst, 0)
   where isnull(tz.noMoveDay, 0) >= (
    select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = tz.branchId
   )

   -- заполняем таблицу по всем маркетинговым группам для Созвездия
   insert into #tmpAllMarketingGroupsProductList(
     branchId, regid, drugId, formId, nnt, minQnt, typeCode, marketingType
   )
   select tCPL.branchId, tCPL.regId, tCPL.drugId, tCPL.formId, null, tCPL.minOst, null, 1
   from #tmpAllConstellationProductList tCPL with (nolock)

   -- заполняем таблицу товаров с рекомендованными поставщиками Созвездия
  insert into #tmpMarketingDistrPriority (branchId, regId, distrId, [percent], [priority], drugid, formid)
  select cpl.branchId, cpl.regid, c.CustomerID, null, 0, cpl.drugId, cpl.formId
  from #tmpAllConstellationProductList cpl with (nolock)
  join Miracle.dbo.ConstellationSuppliersActionProduct csa with (nolock) 
  on cpl.actionId = csa.actionId and csa.productId = cpl.productId and csa.[disable] = '0'
  join Miracle.dbo.ConstellationSuppliers cs with (nolock) on cs.id = csa.supplierId and SUBSTRING(cs.tin, 1, 2) = @regionCode
  join Miracle.dbo.Customer c with (nolock) on c.INN = cs.tin and c.[Disable] = '0'
  join #tmpDistrPriority tdp with (nolock) on tdp.distrId = c.CustomerID
  where not exists (
	select 1 
	from Miracle.dbo.ConstellationIgnoreSupplier cis with (nolock) 
	where cis.branchId = cpl.branchId and cis.actionId = csa.actionId and cis.productId = csa.productId and 
	      cis.supplierId = csa.supplierId and cis.[disable] = '0' and isnull(cis.isIgnore, '0') = '1'
  )
  group by cpl.branchId, cpl.regid, c.CustomerID, cpl.drugId, cpl.formId
  
  drop table #tmpAllConstellationProductList

  ------------------------------------------------------------------------------------------------------------
  -- АСНА
  ------------------------------------------------------------------------------------------------------------

   -- заполняем таблицу по всеми маркетинговым группам для АСНЫ, которые есть в #tmpZakazRegIds
   insert into #tmpAllMarketingGroupsProductList(branchId, regid, drugId, formId, nnt, minQnt, typeCode, [required], marketingType)
   select tb.branchId, r.regid, r.DRUGID, r.FORMID, ap.nnt, iif(isnull(ap.qnt, 0) > 0, 1, 0), a.typeCode, iif(ap.qnt <= 4.5, 0, 1), 2
   from #tmpBranch tb with (nolock)
   join Miracle.dbo.ASNABranch ab with (nolock) on tb.branchId = ab.BranchID
   join Miracle.dbo.ASNAAction a with (nolock) on a.storeId = ab.clientId and a.[status] = '0' and @curDate between a.beginDate and a.endDate
   join Miracle.dbo.ASNAActionPlans ap with (nolock) 
   on ap.actionId = a.Id and ap.storeId = ab.clientId and ap.[status] = '0' and MONTH(ap.periodYM) = MONTH(@curDate)
   join Miracle.dbo.BindingsASNARegId t with (nolock) on t.nnt = ap.nnt and t.rrId = ab.rrId
   join #tmpZakazRegIds r with (nolock) on r.REGID = t.regId
   where case when a.typeCode = 9 and ap.qnt between 0.5 and 4.5 then ab.BdnRecomendHighlightInSvodPrice    -- бдн (рекомендуемые)
			  when a.typeCode = 9 and ap.qnt between 27.5 and 31.5 then ab.highlightInSvodPrice -- бдн (обязательные)
			  when a.typeCode = 10 then ab.PackHighlightInSvodPrice				    -- выкладка
			  when a.typeCode = 13 then ab.MarketRangeHighlightInSvodPrice			    -- маркетинговый ассортимент
			  when a.typeCode = 15 then ab.ProductOfTheDayHighlightInSvodPrice		    -- товар дня
			  when a.typeCode = 16 then ab.USTMHighlightInSvodPrice end = '1'		    -- устм
   group by tb.branchId, r.regId, r.drugId, r.formId, ap.nnt, ap.qnt, a.typeCode

   -- заполняем по @typeID = 9 - Бездефектурное наличие (Обязательное)
   insert into #tmpASNABDNProductList(
    branchId, regid, drugId, formId, minQnt
   )
   select tAMG.branchId, tAMG.regId, tAMG.drugId, tAMG.formId, tAMG.minQnt 
   from #tmpAllMarketingGroupsProductList tAMG with (nolock)
   where tAMG.typeCode = @typeId and [required] = 1 and marketingType = 2

   -- процент для игнора поставщика пока только для АСНА
   insert into #tmpMarketingIgnorePercent (branchId, [percent])
   select b.branchId, iif(cp.value = '', 0, cast(replace(cp.value, ',', '.') as numeric(15, 5)))
   from Miracle.dbo.CustomerParams cp with (nolock)
   join #tmpBranch b with (nolock) on b.branchId = cp.CustomerFillID
   where cp.Name = 'mPercIgnorSupplier'

   -- список маркетинговых товаров с рекомендованными поставщиками АСНА
   insert into #tmpMarketingDistrPriority (branchId, regId, distrId, [percent], [priority], drugid, formid)
   select tmi.BranchID, tpl.regId, c.CustomerID, tmi.[percent], 0, tpl.drugid, tpl.formid
   from #tmpMarketingIgnorePercent tmi with (nolock)
   join #tmpAllMarketingGroupsProductList tpl with (nolock) on tpl.branchId = tmi.branchId
   join Miracle.dbo.ASNARecommendedSuppliers asr with (nolock) on asr.disable = '0' and asr.nnt = tpl.nnt and asr.endDate > GETDATE()
    and SUBSTRING(asr.inn, 1, 2) = @regionCode
   join Miracle.dbo.Customer c with (nolock) on c.inn = asr.inn
   join #tmpDistrPriority tdp with (nolock) on tdp.distrId = c.CustomerID
   left join Miracle.dbo.ASNAIgnoreRecommendedSuppliers air with (nolock) on air.BranchID in (select tb.branchId from #tmpBranch tb)
    and air.nnt = asr.nnt and air.isIgnore = '0'
   where isnull(air.isIgnore, '0') = '0' and marketingType = 2
   group by tmi.branchId, tpl.regID, c.CustomerID, tmi.[percent], tpl.drugid, tpl.formid

   ---------------------------------------------------------------------------------------------------
   -- Избавляемся от рекомендованных поставщиков или товаров в целом без предложений, ИЛИ
   -- тех поставщиков, чья цена превышает минимальную на определнный в настройках поставщика процент
   ---------------------------------------------------------------------------------------------------
   
   -- получам минимальную цену по товару связанному с рекомендованным поставщиком
   update #tmpMarketingDistrPriority
   set minPrice = f.minPrice
   from (
    select min(price) as minPrice, tpl.drugId, tpl.formId, tmd.branchId
    from #tmpMarketingDistrPriority tmd
    join #tmpPriceList tpl on tpl.drugId = tmd.drugId and tmd.formId = tpl.formId
    join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId
    group by tpl.drugId, tpl.formId, tmd.branchId
   ) f
   where #tmpMarketingDistrPriority.drugId = f.drugId and #tmpMarketingDistrPriority.formId = f.formId and
	 #tmpMarketingDistrPriority.branchId = f.branchId

   -- получаем цену рекомендованного поставщика
   update tmd
   set distrPrice = tpl.price
   from #tmpMarketingDistrPriority tmd
   join #tmpPriceList tpl on tpl.regId = tmd.regId and tpl.distrId = tmd.distrId

   -- удаляем рекомендованных поставщиков у товаров, у которых нет минимальной цены или нет цены поставщика - значит нет предложений, 
   -- либо тех, чья цена превышает минимальную на определнный в настройках поставщика процент, если он больше нуля
   delete tmd
   from #tmpMarketingDistrPriority tmd
   where (tmd.minPrice is null) or (tmd.distrPrice is null) or 
	 (tmd.[percent] > 0 and tmd.distrPrice > (tmd.minPrice + ((tmd.minPrice/100) * tmd.[percent])))

   drop table #tmpMarketingIgnorePercent
   drop table #tmpAllMarketingGroupsProductList
   drop table #tmpZakazRegIds

 end

 -- =============================================================================================
 -- Блок работы с маркетингами конец
 ------------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------------------------
 -- Блок проставления макретинговой/матричной потребности начало
 -- =============================================================================================

 /*
 @important т.к маркетинг/матрицы привязываются по regId на этом этапе мы можем предположить,
 что товар со связкой по drugId + formId теоритически может быть заказан на нужного производителя,
 после размещения товара в заказе будет проверка по regId, и если ожидания не оправдались - товар удаляется
 */

 -- заходим сюда если это не обновление по актуальному прайс-листу, иначе потребность уже проставлена как надо
 if @type_update = '0'
 begin

 -- таблица товаров, у которых потребность по уходимости = 0, но теоритически потребность по матрицам/маркетингу есть
 create table #tmpMarketingMatrixNeedProducts (
  autoZakazDataId int, 	   -- идентификатор рассчитанной потребности товара
  branchId int,		   -- филиал
  drugId int,		   -- идентификатор наименования товара
  formId int,		   -- идентификатор формы выпуска товара
  parentDrugId int,	   -- родительский идентификатор наименования товара
  parentFormId int,	   -- родительский идентифиатор формы выпуска товара
  zakazOrig int		   -- новая потребность
 )

 --------------------------------------------------------------------------------------------
 -- проставляем теоритическую потребность на основе маркетинга/матриц у товаров у которых потребность меньше новой
 --------------------------------------------------------------------------------------------

 -- по обязательной матрице созвездия
 update tz
 set zakazOrig = iif(oa.minQnt - tz.ost - tz.tovInAWay <= 0, 0, oa.minQnt - tz.ost - tz.tovInAWay),
     zakaz = iif(oa.minQnt - tz.ost - tz.tovInAWay <= 0, 0, oa.minQnt - tz.ost - tz.tovInAWay)
 output inserted.autoZakazDataId, inserted.branchId, inserted.drugId, inserted.formId, inserted.parentDrugId, inserted.parentFormId, inserted.zakazOrig
 into #tmpMarketingMatrixNeedProducts(autoZakazDataId, branchId, drugId, formId, parentDrugId, parentFormId, zakazOrig)
 from #tmpZakaz tz
 outer apply (
   select max(tcmp.minOst) as minQnt, tcmp.branchId, tcmp.drugId, tcmp.formId
   from #tmpConstellationMatrixProductList tcmp
   where tcmp.branchId = tz.branchId and tcmp.drugId = tz.drugId and tcmp.formId = tz.formId
   group by tcmp.branchId, tcmp.drugId, tcmp.formId
 ) oa
 where (iif(oa.minQnt - tz.ost - tz.tovInAWay <= 0, 0, oa.minQnt - tz.ost - tz.tovInAWay) > tz.zakazOrig) and
 -- в обязательной матрице созвездия
 exists (select 1 from #tmpConstellationMatrixProductList tc where tc.branchId = tz.branchId and tc.drugId = tz.drugId and tc.formId = tz.formId)

 --------------------------------------------------------------------------------------------

 -- проделываем тоже самое, только с БДН АСНА
 update tz
 set zakazOrig = iif(oa.minQnt - tz.ost - tz.tovInAWay > 0, oa.minQnt - tz.ost - tz.tovInAWay, 0),
	 zakaz = iif(oa.minQnt - tz.ost - tz.tovInAWay > 0, oa.minQnt - tz.ost - tz.tovInAWay, 0) 
 output inserted.autoZakazDataId, inserted.branchId, inserted.drugId, inserted.formId, inserted.parentDrugId, inserted.parentFormId, inserted.zakazOrig
 into #tmpMarketingMatrixNeedProducts(autoZakazDataId, branchId, drugId, formId, parentDrugId, parentFormId, zakazOrig)
 from #tmpZakaz tz
 outer apply (
   select max(tapl.minQnt) as minQnt, tapl.branchId, tapl.drugId, tapl.formId
   from #tmpASNABDNProductList tapl
   where tapl.branchId = tz.branchId and tapl.drugId = tz.drugId and tapl.formId = tz.formId
   group by tapl.branchId, tapl.drugId, tapl.formId
 ) oa
 where (iif(oa.minQnt - tz.ost - tz.tovInAWay > 0, oa.minQnt - tz.ost - tz.tovInAWay, 0) > tz.zakazOrig) and
 exists (select 1 from #tmpASNABDNProductList ta where ta.branchId = tz.branchId and ta.drugId = tz.drugId and ta.formId = tz.formId)

 --------------------------------------------------------------------------------------------

 -- аналогично для матричных товаров
 update tz
 set zakazOrig = iif(oa.minQnt - tz.ost - tz.tovInAWay > 0, oa.minQnt - tz.ost - tz.tovInAWay, 0),
     zakaz = iif(oa.minQnt - tz.ost - tz.tovInAWay > 0, oa.minQnt - tz.ost - tz.tovInAWay, 0) 
 output inserted.autoZakazDataId, inserted.branchId, inserted.drugId, inserted.formId, inserted.parentDrugId, inserted.parentFormId, inserted.zakazOrig
 into #tmpMarketingMatrixNeedProducts(autoZakazDataId, branchId, drugId, formId, parentDrugId, parentFormId, zakazOrig)
 from #tmpZakaz tz
 outer apply (
   select max(tmd.minOst) as minQnt, tmd.branchId, tmd.drugId, tmd.formId
   from #tmpMatrixData tmd
   where tmd.branchId = tz.branchId and tmd.drugId = tz.drugId and tmd.formId = tz.formId
   group by tmd.branchId, tmd.drugId, tmd.formId
 ) oa
 where (iif(oa.minQnt - tz.ost - tz.tovInAWay > 0, oa.minQnt - tz.ost - tz.tovInAWay, 0) > tz.zakazOrig) and
 exists (select 1 from #tmpMatrixData tm where tm.branchId = tz.branchId and tm.drugId = tz.drugId and tm.formId = tz.formId)

 --------------------------------------------------------------------------------------------

 -- группируем итоговый список
 insert into #tmpGroupedMarketingMatrixNeedProducts(autoZakazDataId, branchId, drugId, formId, parentDrugId, parentFormId, zakazOrig)
 select autoZakazDataId, branchId, drugId, formId, parentDrugId, parentFormId, max(zakazOrig)
 from #tmpMarketingMatrixNeedProducts tmm
 group by autoZakazDataId, branchId, drugId, formId, parentDrugId, parentFormId

 --------------------------------------------------------------------------------------------

 -- обновляем родительские данные
 update tzp
 set zakazOrig = tgm.zakazOrig, zakaz = tgm.zakazOrig
 from #tmpZakazParent tzp
 join #tmpGroupedMarketingMatrixNeedProducts tgm  
 on tzp.parentDrugId = tgm.parentDrugId and tzp.parentFormId = tgm.parentFormId and tzp.branchId = tgm.branchId and tzp.zakazOrig != tgm.zakazOrig

 --------------------------------------------------------------------------------------------

 -- удаляем товары с нулевой потребностью, т.к они даже теоритически не должны попасть в заказ
 update tzp
 set complete = 1
 from #tmpZakazParent tzp
 where isnull(tzp.zakazOrig, 0) = 0 and
 not exists (
	select 1 
	from #tmpGroupedMarketingMatrixNeedProducts tgm 
	where tgm.branchId = tzp.branchId and tgm.parentDrugId = tzp.parentDrugId and tgm.parentFormId = tzp.parentFormId
 )

 -- удаление родительских товаров с нулевой потребностью
 update tz
 set complete = 1
 from #tmpZakaz tz 
 where isnull(zakazOrig, 0) = 0 or 
 not exists (select 1 from #tmpZakazParent tzp where tzp.branchId = tz.branchId and tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId)

 --------------------------------------------------------------------------------------------

 drop table #tmpMarketingMatrixNeedProducts

 --------------------------------------------------------------------------------------------

 end

 -- =============================================================================================
 -- Блок проставления макретинговой/матричной потребности конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок размещения перемещений в заказе начало
 -- =============================================================================================

 if @donor = '1'
  begin

  -----------------------------------------------------------------------
  -- отсортированный список предложений к перемещению
  -----------------------------------------------------------------------
  create table #tmpMoveOffersList (
   naklDataId bigint,		  -- ссылка на приходную накладную товара
   branchId int,		  -- идентификатор филиала получателя
   donorBranchId int,		  -- идентификатор филиала донора
   regId int,			  -- идентификатор товара с учетом производителя
   drugId int,			  -- идентификатор наименования товара
   formId int,			  -- идентификатор формы выпуска товара
   parentDrugId int,		  -- идентификатор родительского наименования
   parentFormId int,		  -- идентификатор родительской формы
   maxZakaz int,		  -- максимальный заказ по товару
   qntOst int,			  -- текущие остатки товара
   priceFabr numeric(15, 2),  	  -- цена производителя
   pNumber int			  -- номер строки, сгруппированный по родительскому товару
  )

  -------------------------------------------------------------------------
  -- заполняем предложения к перемещению
  -------------------------------------------------------------------------

  insert into #tmpMoveOffersList(
	naklDataId, branchId, donorBranchId, regid, drugId, formId, parentDrugId, parentFormId, maxZakaz, qntOst, priceFabr, pNumber
  )
  select tp.naklDataId, tz.branchId, tp.donorBranchId, tp.regid, tz.drugId, tz.formId, tz.parentDrugId, tz.parentFormId, tp.maxZakaz, tp.qntOst, tp.priceFabr,
         row_number() over ( partition by tz.parentDrugId,tz.parentFormId 
							 order by tp.srokG asc,	    -- самый низкий срок годности
								  tp.maxZakaz desc, -- максимальное кол-во, которое донор может отдать
								  tp.qntOst desc,   -- фактический остаток
								  tp.naklDataId	    -- идентификатор накладной
	) [pNumber]
  from #tmpZakaz tz with (nolock)
  join #tmpMove tm on tm.recepientBranchId = tz.branchId
  join #tmpPriceList tp with (nolock, index = Ind1) on tz.drugId = tp.drugId and tz.formId = tp.formId and tp.donorBranchId = tm.donorBranchId
  left join #tmpDonorSrokG s with (nolock) on s.branchId = tp.donorBranchId
  where 
  ---------------------------------------------------------------------------------
  -- проверка на неликвид. Обычный товар, без матрицы, маркетингов: асны, созвездия
  ---------------------------------------------------------------------------------
  (
	isnull(tz.noMoveDay, 0) < (select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = tz.branchId) 
	and not exists ( -- не в матрице
		select 1
		from #tmpMatrixData tu with (nolock)
		where tu.regId = tp.regId and tu.branchId = tz.branchid
	) 
	and not exists ( -- не в созвездии
		select 1
		from #tmpConstellationMatrixProductList tpl with (nolock)
		where tpl.regId = tp.regId and tpl.branchId = tz.branchId
	) 
	and not exists ( -- не в АСНА
	    select 1
		from #tmpASNABDNProductList tam with (nolock)
		where tam.regid = tp.regId and tam.branchId = tz.branchId
		)
  ) or
  -----------------------------------------------------------------------
  -- товар из созвездия, с не выполненым планом
  (
    exists (-- в созвездии
        select 1 
	    from #tmpConstellationMatrixProductList tcpl with (nolock) 
	    where tcpl.branchId = tz.branchId and tcpl.regId = tp.regId
    ) 
	and not exists (-- план не выполнен
        select 1 
	    from #tmpConstellationMatrixCompleteList tcpl with (nolock) 
	    where tcpl.branchId = tz.branchId and tcpl.regId = tp.regId
    )
  ) or
  -----------------------------------------------------------------------
  -- товар из АСНА бдн с не выполненым планом
  (
    exists ( -- в АСНА
	    select 1
	    from #tmpASNABDNProductList tam with (nolock)
	    where tam.regid = tp.regId and tam.branchId = tz.branchId
	)
	and not exists ( -- план не выполнен
	    select 1
	    from #tmpASNABDNProductList tam with (nolock)
	    left join #tmpZakaz tz2 with (nolock) on tz.autoZakazDataId = tz2.autoZakazDataId and tam.drugId = tz2.drugId and tam.formId = tz2.formId
	    where tam.regid = tp.regId and tam.branchId = tz2.branchId and tz2.ost + tz2.tovInAWay >= tam.minQnt and tz2.zakazOrig < tam.minQnt
	)
  ) or
  -----------------------------------------------------------------------
  -- товар из матрицы с не выполненым планом
  (
    exists ( -- в матрице
        select 1
        from #tmpMatrixData tu with (nolock)
        where tu.regId = tp.regId and tu.branchId = tz.branchid
    )
	and not exists ( -- план не выполнен
        select 1
        from #tmpMatrixData tu with (nolock)
	left join #tmpZakaz tz2 with (nolock) on tz.autoZakazDataId = tz2.autoZakazDataId and tu.drugId = tz2.drugId and tu.formId = tz2.formId
        where tu.regId = tp.regId and tu.branchId = tz2.branchid and tz2.ost + tz2.tovInAWay >= tu.minOst and tz2.zakazOrig < tu.minOst
    )
  ) and
  -----------------------------------------------------------------------
  -- товар не находится в матрице исключения
  not exists (select 1 from #tmpMatrixData t where t.outOfAutoOrder = 1 and t.regId = tp.regId and tz.branchId = t.branchId) and
  -- проходит по сроку годности из настроек срока по перемещению
  datediff(day, @curDate, tp.srokG) >= s.srokGInDayForMove

  -----------------------------------------------------------------------
  -- конец заполнения предложений к перемещению
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------
  -- размещение перемещений в заказе
  -----------------------------------------------------------------------

  -- пытаемся переместить позиции, у которых предложение >= потребности
  insert into #tmpOrder(
	autoZakazDataId, branchId, regId, drugId, formId, parentDrugId, parentFormId, donorBranchId, naklDataId, zakaz, isNew, priceFabr
  )
  select oa.autoZakazDataId, tz.branchId, oa.regId, oa.drugId, oa.formId, oa.parentDrugId, oa.parentFormId, oa.donorBranchId, oa.naklDataId,
  zakazOrig, '1', oa.priceFabr
  from #tmpZakazParent tz
  outer apply (
   select top 1 tm.*, tz2.autoZakazDataId
   from #tmpMoveOffersList tm
   left join #tmpZakaz tz2 on tz2.drugId = tm.drugId and tz2.formId = tm.formId and tz2.branchId = tm.branchId
   where tz.parentDrugId = tm.parentDrugId and tz.parentFormId = tm.parentFormId and tz.branchId = tm.branchId and tz.zakazOrig <= tm.maxZakaz
   order by tm.pNumber asc
  ) oa
  where tz.branchId = oa.branchId and tz.parentDrugId = oa.parentDrugId and tz.parentFormId = oa.parentFormId

  -- пытаемся добавить в перемещение несколько партий сразу, где предложение меньше потребности
  insert into #tmpOrder(
	autoZakazDataId, branchId, regId, drugId, formId, parentDrugId, parentFormId, donorBranchId, naklDataId, zakaz, isNew, priceFabr
  )
  select oa.autoZakazDataId, tz.branchId, oa.regId, oa.drugId, oa.formId, oa.parentDrugId, oa.parentFormId, oa.donorBranchId, oa.naklDataId,
  iif(rs > zakazOrig, zakazOrig + maxZakaz - rs , maxZakaz), '1', oa.priceFabr
  from #tmpZakazParent tz
  outer apply (
   select top 10 tm.*, tz2.autoZakazDataId,
   coalesce(sum(tm.maxZakaz) over (order by tm.pNumber rows between unbounded preceding and current row), 0) as rs
   from #tmpMoveOffersList tm
   left join #tmpZakaz tz2 on tz2.drugId = tm.drugId and tz2.formId = tm.formId and tz2.branchId = tm.branchId
   where tz.parentDrugId = tm.parentDrugId and tz.parentFormId = tm.parentFormId and tz.branchId = tm.branchId and tz.zakazOrig > tm.maxZakaz
   order by tm.pNumber asc
  ) oa
  where tz.branchId = oa.branchId and tz.parentDrugId = oa.parentDrugId and tz.parentFormId = oa.parentFormId and rs - maxZakaz < tz.zakazOrig and
  not exists (select 1 from #tmpOrder t where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId)
  order by tz.parentDrugId, tz.parentFormId

  drop table #tmpMoveOffersList

  --=====================================================================
  -- размещение закончено
  -----------------------------------------------------------------------

  -- уменьшение потребностей перемещенных товаров
  if exists (select 1 from #tmpOrder where donorBranchId is not null)
   begin

    -----------------------------------------------------

    -- удаляем уже размещенные позиции прайс-листа
    delete
    from #tmpPriceList
    where naklDataId in (select o.naklDataId from #tmpOrder o with (nolock) where o.naklDataId is not null and o.isNew = '1')

	-----------------------------------------------------

    -- уменьшаем потребности
    ;with t as (
      select o.branchId, o.parentDrugId, o.parentFormId, sum(o.zakaz) sumZak
      from #tmpOrder o with (nolock)
      where o.isNew = '1'
      group by o.parentDrugId, o.parentFormId, o.branchId
     )

    update tzp
    set tzp.zakaz = tzp.zakaz - t.sumZak
    from #tmpZakazParent tzp with (nolock)
    join t on t.parentDrugId = tzp.parentDrugId and tzp.parentFormId = t.parentFormId and t.branchId = tzp.branchId

	-- уменьшаем потребности
    ;with t as (
      select o.autoZakazDataId, sum(o.zakaz) sumZak
      from #tmpOrder o with (nolock)
      where o.isNew = '1'
      group by o.autoZakazDataId
     )

    update tz
    set zakaz = tz.zakaz - t.sumZak
    from #tmpZakaz tz with (nolock)
    join t on t.autoZakazDataId = tz.autoZakazDataId

	-----------------------------------------------------

    -- удаляем удовлетворенные потребности
    ;with t as (
      select tz.autoZakazDataId
      from #tmpZakaz tz with (nolock)
      left join #tmpZakazParent tzp with (nolock)
      on tz.parentDrugId = tzp.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
      where tzp.zakaz <= 0 and isnull(tz.zakazOrig, 0) > 0
     )

     update #tmpZakaz
     set zakaz = 0, complete = 1
     where autoZakazDataId in (select autoZakazDataId from t with (nolock))

     update #tmpZakazParent
     set zakaz = 0, complete = 1
     where zakaz <= 0 and isnull(zakazOrig, 0) > 0

     update #tmpOrder
     set isNew = '0'

	 -----------------------------------------------------

   end

  -- если после размещения перемещений заказывать нечего - проставляем признак того, что заказ готов.
  if not exists(select 1 from #tmpZakaz) set @orderDone = 1

  end

 -- =============================================================================================
 -- Блок размещения перемещений в заказе конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок размещения товаров в заказе по предложениям поставщикиков из прайс-листа начало
 -- =============================================================================================

 if @orderDone = 0
  begin

  create table #tmpOffersList(
   autoZakazdataId int,		  -- ссылка на расччитанную потребность товара
   branchId int,		  -- идентификатор филиала
   regId int,			  -- идентификатор товара с учетом производителя
   drugId int,			  -- идентификатор наименования товара
   formId int,			  -- идентификатор формы выпуска товара
   parentDrugId int,		  -- идентификатор наименования родительского товара
   parentFormId int,		  -- идентификатор формы родительского товара
   zakaz numeric(15, 5),	  -- рассчитанная сумма заказа
   distrId int,			  -- идентификатор поставщика
   priceId bigint,		  -- идентификатор предложения поставщика в прайсе
   price numeric (15, 2),	  -- цена у поставщика
   priceFabr numeric (15, 2), 	  -- цена производителя
   priceOst int,		  -- остатки товара у поставщика
   minZakaz int,		  -- минимальный заказ у поставщика
   ratio int,			  -- кратность товара поставщика
   pNumber int,			  -- порядковый номер предложения отсортированный по минимальной цене
   isNew char(1)		  -- признак нового товара в заказе
  )

   ------------------------------------------------------------------------------------------------------------------
   -- Сортировка предложений поставщиков, для размещения по минимальной цене
   ------------------------------------------------------------------------------------------------------------------

   -- todo 15% поправить все инсерты сюда
     insert into #tmpPriceListIdList (priceId, branchId, pNumber)
     select tp.priceId, tz.branchId, 
	    row_number() over (
	    partition by tz.parentDrugId,tz.parentFormId,tz.branchId
       	    order by
	    -- подходящие значения кратности и мин заказа
	    iif(tzp.zakaz >= tp.minZakaz and tz.zakaz % tp.ratio = 0, 0, 1),
	    -- условная цена для сортировки. Чем выше цена - тем товар в списке на размещение ниже
	    tp.price * isnull(dp.[priority], 1) * isnull(fp.[priority], 1),
	    tp.srokG desc, tp.qntOst desc, tp.priceId
	  ) [pNumber]
     from #tmpZakaz tz with (nolock)
     join #tmpZakazParent tzp with (nolock)
     on tzp.branchId = tz.branchId and tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId
     join #tmpPriceList tp with (nolock, index = Ind1) on tp.drugId = tz.drugId and tp.formId = tz.formId
     left join #tmpDistrPriority dp with (nolock, index = Ind1) on dp.distrId = tp.distrId and dp.branchId = tz.branchId
     left join #tmpFabrPriority fp with (nolock) on tp.regId = fp.regId
     left join #tmpAutoZakazProfile tAZP with (nolock) on tAZP.branchId = tz.branchId -- добавили JOIN ля условия
     where tp.distrId is not null and tp.[block] = '0' and tz.complete = 0 and 
	   (tAZP.excludeDiscounted = '1' and tp.nacenk = '0' or tAZP.excludeDiscounted = '0')
     option (optimize for unknown)

     -- ============================================================================================================ --
     -- СОБИРАЕМ ПРЕДЛОЖЕНИЯ ПОСТАВЩИКОВ К ЗАКАЗУ
     -- ============================================================================================================ --

     ------------------------------------------------------------------------------------------------------------
     -- считаем кол-во уже заказанных позиций по каждому товару --TODO проверить, не вижу смысла, т.к заказ размещается только здесь и за 1 раз
     -- =======================================================================================================--
     ;with cteProductsOrders as (
      select drugId, formId, sum(zakaz) sumZak, branchId from #tmpOrder with (nolock) group by drugId, formId, branchId
     ), 
     -- =======================================================================================================--
     -- собираем предложения поставщиков, отсекаем не матричные товары.
     -- =======================================================================================================--
     ctePricePart1 as (
       select tp.priceId, tp.matrixTitleId, s.srokGInMonth, z.branchId, tp.distrId, z.drugId, z.formId, tp.minOst, tp.minZakaz, tzp.ost, tp.regId,
	      tzp.tovInAWay, r.sumZak, tp.ratio, tzp.threshold1, tzp.threshold2, tp.srokG, tzp.zakaz, tp.qntOst as priceOst, tp.porogZakaz, pil.pNumber,
	      z.noMoveDay, z.autoZakazDataId, z.parentDrugId, z.parentFormId, tp.price, tp.priceFabr,
	      -- заказ увеличенный по кратности
              ((tzp.zakaz + tp.ratio) - (tzp.zakaz % tp.ratio)) zakazRatioUp,
              -- заказ уменьшенный по кратности
              (tzp.zakaz - (tzp.zakaz % tp.ratio)) zakazRatioDown,
              -- заказ увеличенный до требуемого минимума и увеличенный по кратности
	      iif(tp.minZakaz = tp.ratio, tp.minZakaz, ((tp.minZakaz + tp.ratio) - (tp.minZakaz % tp.ratio))) zakazUnion
       from #tmpPriceList tp with (index = Ind1)
       join #tmpZakaz z on z.drugId = tp.drugId and z.formId = tp.formId
       join #tmpPriceListIdList pil on pil.priceId = tp.priceId and pil.branchId = z.branchId
       join #tmpDistrPriority dp with (index = Ind1) on z.branchId = dp.branchId and tp.distrId = dp.distrId
       left join #tmpZakazParent tzp 
       on tzp.parentDrugId = z.parentDrugId and tzp.parentFormId = z.parentFormId and tzp.branchId = z.branchId and tzp.complete = 0
       left join cteProductsOrders r on r.branchId = z.branchId and r.drugId = tp.drugId and r.formId = tp.formId
       left join #tmpSrokG s on s.branchId = z.branchId
       where 
       -- @type_update - 1 - перезаказ по тому же поставщику, иначе по минимальной цене
       (@type_update != '1' or (@type_update = '1' and tp.distrId = isnull(z.distrId, tp.distrId))) and 
       -- товар не находится в матрице исключения
       not exists (select 1 from #tmpMatrixData t where t.outOfAutoOrder = 1 and t.regId = tp.regId and z.branchId = t.branchId) and
       (
	-- если товар не матричный
        (tp.matrixTitleId is null or tp.minOst < 1) and
	-- проходящий по сроку годности
	(datediff(month, @curDate, tp.srokG) >= s.srokGInMonth or @srokG = '0') and 
	(
	  -- заказ больше или равен минимальному заказу
	  (tzp.zakaz >= tp.minZakaz) or
	  -- если меньше мин. заказа - увеличение по кратности до требуемого минимума + проверка на продажу за 20 дней.
          (iif(tp.minZakaz = tp.ratio, tp.minZakaz, (tp.minZakaz + tp.ratio) - (tp.minZakaz % tp.ratio)) <= tzp.threshold2 - isnull(r.sumZak, 0))
        ) and
	(
	 -- заказ либо кратный, либо проходящий по продаже за 20 дней
	 (tzp.zakaz % tp.ratio = 0) or (((tzp.zakaz + tp.ratio) - (tzp.zakaz % tp.ratio)) <= tzp.threshold2 - isnull(r.sumZak, 0)) or
         (
	 -- если заказ больше кратности, уменьшение до нужной кратности
	 (tzp.zakaz > tp.ratio) and ((tzp.zakaz - (tzp.zakaz % tp.ratio)) >= tzp.threshold2 - isnull(r.sumZak, 0))
	 )
        )
       ) or
       -- либо товар матричный, отсекаем его в следующем условии, для читабельности
       tp.matrixTitleId is not null
       ), 
       -- =======================================================================================================--
       -- отсекаем матричные товары
       -- =======================================================================================================--
       ctePricePart2 as (
	   select c.priceId, c.drugId, c.formId, c.distrId, c.zakaz, c.zakazRatioUp, c.zakazRatioDown, c.zakazUnion, c.porogZakaz, c.ratio, c.minZakaz, c.price,
		  c.threshold2, c.sumZak, c.pNumber, c.regId, c.branchId, c.noMoveDay, c.autoZakazDataId, c.ost, c.parentDrugId, c.parentFormId, c.priceFabr,
		  c.priceOst, c.tovInAWay,
	   	  -- заказ для матричного товара
       		  iif(c.matrixTitleId > 0, 
			iif(c.zakaz > c.minOst, c.zakaz,
		 		iif(c.minOst - c.ost - c.tovInAWay > 0, c.minOst - c.ost - c.tovInAWay, 0)), 0) zakazMatrix
	   from ctePricePart1 c
	   left join #tmpMatrixDistr md with (nolock) on c.branchId = md.branchId and c.matrixTitleId = md.matrixTitleId
	   where
	       (
	        -- товар матричный
		exists (select 1 from #tmpMatrixData t where t.regId = c.regId and t.branchId = c.branchId) and c.matrixTitleId > 0
		-- срок годности
	        and (datediff(month, @curDate, c.srokG) >= c.srokGInMonth or @srokG = '0')
	        -- учёт матричного поставщика, если есть приоритет
	        and c.distrId = iif(md.distrId is null, c.distrId, md.distrId) and 
		(
	         -- Соответствие минимальному заказу поставщика
	         (isnull(c.minOst, 0) - isnull(c.ost, 0) - isnull(c.tovInAWay, 0) >= c.minZakaz) or
	         -- Минимальный заказ не превышающий 20-ти дневный прогноз
	         ((c.minZakaz + c.ratio) - (c.minZakaz % c.ratio) <= c.threshold2 - isnull(c.sumZak, 0) or c.threshold2 = 0)
	        )
	        -- кратность
	        and (c.minOst - c.ost - c.tovInAWay) % c.ratio = 0
	       ) 
	       -- либо товар не матричный, мы их проверили выше
	       or c.matrixTitleId is null
	  ),
	  -- =======================================================================================================--
	  -- считаем итоговый заказ
	  -- =======================================================================================================--
	 ctePricePart3 as (select 
	 case
      	 -- Если товар матричный
      	 when c.zakazMatrix > c.zakaz then case when c.zakazMatrix < c.porogZakaz then c.porogZakaz else c.zakazMatrix end
      	 -- Если товар не матричный
      	 when c.zakazMatrix <= c.zakaz 
	 then case
              -- Если заказ больше чем требуемый минимум либо равен ему
              when c.zakaz >= c.minZakaz
	      then case
		   -- если заказ кратный
                   when c.zakaz % c.ratio = 0 then c.zakaz
		   -- если заказ не кратный и можно увеличить
                   when c.zakazRatioUp <= c.threshold2 - isnull(c.sumZak, 0) then c.zakazRatioUp
		   -- если заказ не кратный и надо уменьшить
                   when c.zakazRatioDown >= c.threshold2 - isnull(c.sumZak, 0) then c.zakazRatioDown 
                   end
              -- Если заказ меньше чем требуемый минимум
              else case
		   -- если мин заказ кратный и можно увеличить
               	   when c.minZakaz % c.ratio = 0 and c.minZakaz <= c.threshold2 - isnull(c.sumZak, 0) then c.minZakaz
		   -- если мин заказ не кратный и можно увеличить
                   when c.zakazUnion <= c.threshold2 - isnull(c.sumZak, 0) then c.zakazUnion
              	   end
              end
          else 0 
	  end as zakaz, c.regId, c.drugId, c.formId, c.branchId, c.priceId, c.minZakaz, c.ratio, c.distrId, c.pNumber, c.noMoveDay, c.autoZakazDataId, c.ost,
		 c.parentDrugId, c.parentFormId, c.price, c.priceFabr, c.priceOst, c.tovInAWay
	  from ctePricePart2 c
	 ),
	 -- =======================================================================================================--
	 -- проверка на неликвид, отбрасываем неликвидные позиции из размещения
	 -- =======================================================================================================--
	 ctePricePart4 as (
	  select *, '1' as isNew
	  from ctePricePart3 o
	  where
	  -- обычный товар, без матрицы, маркетингов: асны, созвездия
	  (
	   isnull(o.noMoveDay, 0) < (select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = o.branchId) 
	   and not exists ( -- не в матрице
		select 1
		from #tmpMatrixData tu with (nolock)
		where tu.regId = o.regId and tu.branchId = o.branchid
	   ) 
	   and not exists ( -- не в созвездии
		select 1
		from #tmpConstellationMatrixProductList tpl with (nolock)
		where tpl.regId = o.regId and tpl.branchId = o.branchId
	   ) 
	   and not exists ( -- не в АСНА
	    select 1
		from #tmpASNABDNProductList tam with (nolock)
		where tam.regid = o.regId and tam.branchId = o.branchId
		)
	  ) or
      	  -- товар из созвездия, с не выполненым планом
      	  (
	   exists (-- в созвездии
            select 1 
	    from #tmpConstellationMatrixProductList tcpl with (nolock) 
	    where tcpl.branchId = o.branchId and tcpl.regId = o.regId
       	   ) 
	   and not exists (-- план не выполнен
            select 1 
	    from #tmpConstellationMatrixCompleteList tcpl with (nolock) 
	    where tcpl.branchId = o.branchId and tcpl.regId = o.regId
       	   )
	  ) or
	  -- товар из АСНА бдн с не выполненым планом
	  (
	   exists ( -- в АСНА
	    select 1
	    from #tmpASNABDNProductList tam with (nolock)
	    where tam.regid = o.regId and tam.branchId = o.branchId
	   )
	   and not exists ( -- план не выполнен
	    select 1
	    from #tmpASNABDNProductList tam with (nolock)
	    left join #tmpZakaz tz with (nolock) on tz.autoZakazDataId = o.autoZakazDataId and tam.drugId = tz.drugId and tam.formId = tz.formId
	    where tam.regid = o.regId and tam.branchId = o.branchId and o.ost + o.tovInAWay >= tam.minQnt and tz.zakazOrig < tam.minQnt
	   )
	  ) or
	  -- товар из матрицы с не выполненым планом
	  (
	   exists ( -- в матрице
            select 1
            from #tmpMatrixData tu with (nolock)
            where tu.regId = o.regId and tu.branchId = o.branchid
       	   )
	   and not exists ( -- план не выполнен
            select 1
            from #tmpMatrixData tu with (nolock)
	    left join #tmpZakaz tz with (nolock) on tz.autoZakazDataId = o.autoZakazDataId and tu.drugId = tz.drugId and tu.formId = tz.formId
            where tu.regId = o.regId and tu.branchId = o.branchid and o.ost + o.tovInAWay >= tu.minOst and tz.zakazOrig < tu.minOst
           )
	 )
    	)
	-- =======================================================================================================--
	-- проверка на неликвид конец
	------------------------------------------------------------------------------------------------------------

	-- заполняем список предложений на основе условий выше
	insert into #tmpOffersList(autoZakazdataId, branchId, regId, drugId, formId, parentDrugId, parentFormId, zakaz, distrId, priceId, price, priceFabr,
				   priceOst, minZakaz, ratio, pNumber, isNew)
	select autoZakazDataId, branchId, regId, drugId, formId, parentDrugId, parentFormId, zakaz, distrId, priceId, price, priceFabr, priceOst, minZakaz, 
	       ratio, pNumber, isNew
	from ctePricePart4

	-- ============================================================================================================ --
	-- ЗАКОНЧИЛИ СОБИРАТЬ ПРЕДЛОЖЕНИЯ ПОСТАВЩИКОВ
	------------------------------------------------------------------------------------------------------------------

	------------------------------------------------------------------------------------------------------------------
	-- РАЗМЕЩЕНИЕ ПОЗИЦИЙ В ЗАКАЗЕ
	-- ============================================================================================================ --

	-- ============================================================================================================ --
	-- пытаемся разместить заказ по минимальной цене на рекомендованного поставщика с заказом <= остатку поставщика
	------------------------------------------------------------------------------------------------------------------

	insert into #tmpOrder(autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId, zakaz, price, priceId, distrId, isNew, priceFabr)
	select autoZakazdataId, regId, c.branchId, drugId, formId, parentDrugId, parentFormId, zakaz, price, c.priceId, distrId, isNew, priceFabr
	from #tmpOffersList c
	outer apply (
	 select top 1 c2.priceId, c2.branchId
	 from #tmpOffersList c2
	 where c.parentDrugId = c2.parentDrugId and c.parentFormId = c2.parentFormId and c.branchId = c2.branchId and c2.zakaz <= c2.priceOst and 
	 c2.distrId in (
		select tmd.distrId from #tmpMarketingDistrPriority tmd where tmd.drugId = c2.drugId and tmd.formId = c2.formId and tmd.branchId = c2.branchId
	 )
	 order by c2.pNumber asc
	) oa
	where c.priceId = oa.priceId and c.branchId = oa.branchId

	-- ======================================================================================================== --
	-- иначе пытаемся разместить заказ по минимальной цене на любого поставщика с заказом <= остатку поставщика
	--------------------------------------------------------------------------------------------------------------

	insert into #tmpOrder(autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId, zakaz, price, priceId, distrId, isNew, priceFabr)
	select autoZakazdataId, regId, c.branchId, drugId, formId, parentDrugId, parentFormId, zakaz, price, c.priceId, distrId, isNew, priceFabr
	from #tmpOffersList c
	outer apply (
	 select top 1 c2.priceId, c2.branchId
	 from #tmpOffersList c2
	 where c.parentDrugId = c2.parentDrugId and c.parentFormId = c2.parentFormId and c.branchId = c2.branchId and c2.zakaz <= c2.priceOst and 
	 c2.distrId not in (
		select tmd.distrId from #tmpMarketingDistrPriority tmd where tmd.drugId = c2.drugId and tmd.formId = c2.formId and tmd.branchId = c2.branchId
	 )
	 order by c2.pNumber asc
	) oa
	where c.priceId = oa.priceId and c.branchId = oa.branchId and not exists (
	 select 1
	 from #tmpOrder t 
	 where c.parentDrugId = t.parentDrugId and c.parentFormId = t.parentFormId and t.donorBranchId is null and t.branchId = c.branchId
	)

	-- ================================================================================================================ --
	-- пытаемся разместить заказ по минимальной цене на рекомендованного поставщика с заказом больше остатка поставщика
	----------------------------------------------------------------------------------------------------------------------

	insert into #tmpOrder(autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId, zakaz, price, priceId, distrId, isNew, priceFabr)
	select autoZakazdataId, regId, c.branchId, drugId, formId, parentDrugId, parentFormId, oa.zakaz, price, c.priceId, distrId, isNew, priceFabr
	from #tmpOffersList c
	outer apply (
	 select top 1 c2.priceId, c2.branchId,
	      -- если кратный то заказываем минимальный остаток
	 case when c2.priceOst % ratio = 0 then c2.priceOst 
	      -- если не кратный пытаемся уменьшить до кратности с соответствием минимальному остатку
	      when c2.priceOst % c2.ratio > 0 and c2.priceOst - c2.priceOst % c2.ratio >= c2.minZakaz then c2.priceOst - c2.priceOst % c2.ratio
	 end as zakaz
	 from #tmpOffersList c2
	 where c.parentDrugId = c2.parentDrugId and c.parentFormId = c2.parentFormId and c.branchId = c2.branchId and c2.zakaz > c2.priceOst 
	 -- если >= минимальному заказу и кратный, либо не кратный и пытаемся уменьшить до нужной кратности с соответсвием минимальному заказу
	 and c2.priceOst >= c2.minZakaz and (c2.priceOst % c2.ratio = 0 or (c2.priceOst % c2.ratio > 0 and c2.priceOst - c2.priceOst % c2.ratio >= c2.minZakaz))
	 and c2.distrId in (	
		select tmd.distrId from #tmpMarketingDistrPriority tmd where tmd.drugId = c2.drugId and tmd.formId = c2.formId and tmd.branchId = c2.branchId
	 )
	 order by c2.pNumber asc
	) oa
	where c.priceId = oa.priceId and c.branchId = oa.branchId and not exists (
	 select 1 
	 from #tmpOrder t 
	 where c.parentDrugId = t.parentDrugId and c.parentFormId = t.parentFormId and t.donorBranchId is null and t.branchId = c.branchId
	)

	-- ====================================================================================================== --
	-- пытаемся разместить заказ по минимальной цене на любого поставщика с заказом больше остатка поставщика --
	------------------------------------------------------------------------------------------------------------

	insert into #tmpOrder(autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId, zakaz, price, priceId, distrId, isNew, priceFabr)
	select autoZakazdataId, regId, c.branchId, drugId, formId, parentDrugId, parentFormId, oa.zakaz, price, c.priceId, distrId, isNew, priceFabr
	from #tmpOffersList c
	outer apply (
	 select top 1 c2.priceId, c2.branchId,
	      -- если кратный то заказываем минимальный остаток
	 case when c2.priceOst % ratio = 0 then c2.priceOst 
	      -- если не кратный пытаемся уменьшить до кратности с соответствием минимальному остатку
	      when c2.priceOst % c2.ratio > 0 and c2.priceOst - c2.priceOst % c2.ratio >= c2.minZakaz then c2.priceOst - c2.priceOst % c2.ratio
	 end as zakaz
	 from #tmpOffersList c2
	 where c.parentDrugId = c2.parentDrugId and c.parentFormId = c2.parentFormId and c.branchId = c2.branchId and c2.zakaz > c2.priceOst 
	 -- если >= минимальному заказу и кратный, либо не кратный и пытаемся уменьшить до нужной кратности с соответсвием минимальному заказу
	 and c2.priceOst >= c2.minZakaz and (c2.priceOst % c2.ratio = 0 or (c2.priceOst % c2.ratio > 0 and c2.priceOst - c2.priceOst % c2.ratio >= c2.minZakaz))
	 and c2.distrId not in (
		select tmd.distrId from #tmpMarketingDistrPriority tmd where tmd.drugId = c2.drugId and tmd.formId = c2.formId and tmd.branchId = c2.branchId
	 )
	 order by c2.pNumber asc
	) oa
	where c.priceId = oa.priceId and c.branchId = oa.branchId and not exists (
	 select 1 
	 from #tmpOrder t 
	 where c.parentDrugId = t.parentDrugId and c.parentFormId = t.parentFormId and t.donorBranchId is null and t.branchId = c.branchId
	)

   -- удаляем из заказа товары, которые разместились не на предпологаемого производителя из маркетинга/матрицы
   delete t
   from #tmpOrder t
   join #tmpGroupedMarketingMatrixNeedProducts tgm on tgm.autoZakazDataId = t.autoZakazDataId
   where not exists (select 1 from #tmpConstellationMatrixProductList tcmp where t.regId = tcmp.regId and t.branchId = tcmp.branchId) and
		 not exists (select 1 from #tmpASNABDNProductList tap where tap.branchId = t.branchId and tap.regId = t.regId) and
		 not exists (select 1 from #tmpMatrixData tmd where tmd.branchId = t.branchId and tmd.regId = t.regId) and t.donorBranchId is null

   drop table #tmpOffersList
   drop table #tmpGroupedMarketingMatrixNeedProducts

   -- ============================================================================================================ --
   -- ЗАКОНЧИЛИ РАЗМЕЩЕНИЕ
   -- ============================================================================================================ --

   -- уменьшение потребностей у размещенных товаров
   if exists (select 1 from #tmpOrder where donorBranchId is null)
    begin

     -- удаляем уже размещенные позиции прайс-листа
     update #tmpPriceList set ordered = 1
     where priceId in (select o.priceId from #tmpOrder o where o.priceId is not null and o.isNew = '1')

     -- уменьшаем потребности --
     -----------------------------------------

    ;with t as (
      select o.branchId, o.parentDrugId, o.parentFormId, sum(o.zakaz) sumZak
      from #tmpOrder o with (nolock)
      where o.isNew = '1'
      group by o.parentDrugId, o.parentFormId, o.branchId
     )

     update tzp
     set tzp.zakaz = tzp.zakaz - t.sumZak
     from #tmpZakazParent tzp with (nolock)
     join t on t.parentDrugId = tzp.parentDrugId and tzp.parentFormId = t.parentFormId and tzp.branchId = t.branchId

     -----------------------------------------

     -- удаляем удовлетворенные потребности --
     -----------------------------------------
    ;with t as (
      select tz.autoZakazDataId
      from #tmpZakaz tz 
      left join #tmpZakazParent tzp on tz.parentDrugId = tzp.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
      where tzp.zakaz <= 0 and isnull(tz.zakazOrig, 0) > 0
     )

     update #tmpZakaz
     set zakaz = 0, complete = 1
     where autoZakazDataId in (select autoZakazDataId from t)

     update #tmpZakazParent
     set zakaz = 0, complete = 1
     where zakaz <= 0 and isnull(zakazOrig, 0) > 0

     update #tmpOrder
     set isNew = '0'
	 -----------------------------------------
    end

  end

 -- =============================================================================================
 -- Блок размещения товаров в заказе по предложениям поставщикиков из прайс-листа конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок уменьшения лишних перемещений, когда итоговое кол-во заказа больше потребности начало
 -- =============================================================================================

 if @donor = '1'
 begin
 /*
  @important 

  нам нужны только те товары, у которых есть перемещение, иначе это может быть товар, который округлен по кратности в большую сторону
  из за чего фактическое кол-во заказа оказалось больше чем требуемое - это норма.
 */

 -- таблица товаров, у которых из за перемещения фактическое кол-во превышает требуемое
 create table #tmpOrderExceed (
  autoZakazDataId int, -- ссылка на товар
  exceed int	       -- разница между фактическим заказом и потребностью в штуках
 )

 -- собираем товары с перемещением, у которых есть превышение потребности
 insert into #tmpOrderExceed(autoZakazDataId, exceed)
 select autoZakazDataId, zakazFact - zakazOrig
 from (
  select tz.autoZakazDataId, sum(isnull(t.zakaz, 0)) zakazFact, tz.zakazOrig
  from #tmpZakaz tz with (nolock)
  left join #tmpOrder t with(nolock) on tz.autoZakazDataId = t.autoZakazDataId
  where tz.zakazOrig > 0 and exists (select 1 from #tmpOrder t2 where t2.autoZakazDataId = tz.autoZakazDataId and t2.donorBranchId is not null)
  group by tz.autoZakazDataId, tz.zakazOrig
 ) f
 where zakazFact > zakazOrig

 -- если товары с превышением потребности существуют
 if exists (select 1 from #tmpOrderExceed)
  begin

   -- сортировка товаров по наибольшнему заказу с начала
   ;with cte as (
    select oe.autoZakazDataId,
     t.naklDataId,
     oe.exceed,
     row_number() over (partition by oe.autoZakazDataId order by t.zakaz desc) number
    from #tmpOrderExceed oe with (nolock)
    left join #tmpOrder t on oe.autoZakazDataId = t.autoZakazDataId and t.naklDataId is not null
   )

   -- уменьшаем фактический заказ до потребности
   update o
   set o.zakaz = iif(o.zakaz <= cte.exceed, 0, o.zakaz - cte.exceed)
   from #tmpOrder o with(nolock)
   join cte on cte.autoZakazDataId = o.autoZakazDataId and cte.naklDataId = o.naklDataId and cte.number = 1

   -- удаляем товары из размещения, если у них заказ 0 по уменьшению потребности 
   -- (после выполнения блока ограничения заказа - заказ = 0 оставляем, так и должно быть)
   delete from #tmpOrder
   where autoZakazDataId in (select autoZakazDataId from #tmpOrderExceed with(nolock)) and zakaz = 0

  end

 drop table #tmpOrderExceed
 end

 -- =============================================================================================
 -- Блок уменьшения лишних перемещений, когда итоговое кол-во заказа больше потребности конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок ограничения заказа по сумме начало
 -- =============================================================================================

 -- список филиалов и суммы ограничения 
 declare
 @tblPlanOrder table (
   branchid int,			 -- идентификатор филиала
   planOrder numeric(15, 5),		 -- план заказа не текущую дату
   planOrderWOUnexcluded numeric(15, 5), -- плана заказа без учета позиций, которые нельзя исключить
   useRestriction bit			 -- признак того, что ограничение по филиалу включено
 )

 -- если перезаказ по актуальному прайс-листу/расформирование
 if @type_update != '0'
 begin
  -- признак использования ограничения, если в перезаказываемом заказе была сумма ограничения > 0
  update #tmpAutoZakazProfile
  set useRestriction = tb.useRestriction
  from #tmpBranch tb
  where tb.branchId = #tmpAutoZakazProfile.branchId and isnull(tb.restrictionSum, 0) > 0

  -- заполняем планируемую сумму
  insert into @tblPlanOrder(branchid, planOrder, useRestriction)
  select tb.branchId, tb.restrictionSum, tb.useRestriction
  from #tmpBranch tb
  where ISNULL(tb.restrictionSum, 0) > 0
 end

 -- если ограничение необходимо
 if exists(select 1 from #tmpAutoZakazProfile where useRestriction is not null)
 begin

  -- товары с посчитанной суммой накопительного итога
  create table #tmpRankedProductList (
    autoZakazDataId int,       -- ссылка на товар
    branchId int,	       -- идентификатор филиала
    rankedSum numeric (15, 2)  -- сумма с накопительным итогом
  )

  -------------------------------------------------------------------------------------------------------

  -- если не перезаказ по актуальному прайс-листу/не расформирование заказа
  if @type_update = '0'
  begin
    -- заполняем суммы ограничения по филиалам
    insert into @tblPlanOrder(branchid, planOrder, useRestriction)
    select b.BranchId, isnull(ppo.PlanOrder, 0), ta.useRestriction
    from #tmpBranch b with (nolock)
    left join Miracle.dbo.KWPlanProceedsAndOrder ppo with (nolock) on ppo.BranchId = b.branchId and ppo.PlanDate = cast(@curDate as date)
    left join #tmpAutoZakazProfile ta on ta.branchId = b.branchId
    group by b.BranchId, isnull(ppo.PlanOrder, 0), ta.useRestriction

    -- если вдруг где то все равно null проставляем 0
    update @tblPlanOrder 
    set planOrder = 0
    where planOrder is null
  end

  -------------------------------------------------------------------------------------------------------

  -- проставляем сумму ограничения на выход, отсюда она будет сохранена в постоянной таблице
  update tb
  set tb.restrictionSum = tp.planOrder
     ,tb.useRestriction = tp.useRestriction
  from #tmpBranch tb
  join @tblPlanOrder tp on tp.branchid = tb.branchId

  -------------------------------------------------------------------------------------------------------

  -- сразу проставляем комментарий к заказу, где включено ограничение заказа, но отсутствует сумма
  update tb
  set tb.comment = iif(isnull(tb.comment, '') = '', '', tb.comment + ', ') + 'ограничение не выполнено: отсутствует план заказа на дату'
  from #tmpBranch tb
  join @tblPlanOrder t on t.branchid = tb.branchId and t.useRestriction is not null and planOrder <= 0

  -------------------------------------------------------------------------------------------------------
  -- Выполняем ограничение
  -------------------------------------------------------------------------------------------------------

  -- считаем сумму с накопительным итогом у товаров, которые можно исключить
  insert into #tmpRankedProductList (branchId, autoZakazDataId, rankedSum)
  select o.branchId, o.autoZakazDataId, 
  coalesce(sum(o.price * o.zakaz) over (partition by o.branchId order by t.kEff desc, t.drugId asc, t.formId asc
           rows between unbounded preceding and current row), 0) as rankedSum
  from #tmpOrder o
  join @tblPlanOrder tp on tp.branchid = o.branchId
  join #tmpZakaz t on o.autoZakazDataId = t.autoZakazDataId
  where
   tp.planOrder > 0 and
   -- не в обязательной матрице созвездия
   not exists (select 1 from #tmpConstellationMatrixProductList tc where tc.regId = o.regId and tc.branchId = o.branchId) 
   -- не в обязательном бдн асны
   and not exists (select 1 from #tmpASNABDNProductList ta where ta.regId = o.regId and ta.branchId = o.branchId)
   -- не в матрице
   and not exists (select 1 from #tmpMatrixData tu where tu.regId = o.regId and tu.branchId = o.branchId)
   and donorBranchId is null
  order by t.kEff asc, t.drugId desc, t.formId desc

  -------------------------------------------------------------------------------------------------------

  -- считаем планируемую сумму заказа для тех товаров, которые можно исключить
  update tp
  set planOrderWOUnexcluded = tp.planOrder - isnull(oa.unexlucedsum, 0)
  from @tblPlanOrder tp
  outer apply (
   select tz.branchId, sum(tz.zakaz * tz.price) as unexlucedsum
   from #tmpOrder tz with (nolock)
   where (
	-- в обязательной матрице созвездия
	exists (select 1 from #tmpConstellationMatrixProductList tc where tc.regId = tz.regId and tc.branchId = tz.branchId) 
	-- или в обязательном бдн асны
	or exists (select 1 from #tmpASNABDNProductList ta where ta.regId = tz.regId and ta.branchId = tz.branchId)
	-- или в матрице
	or exists (select 1 from #tmpMatrixData tu where tu.regId = tz.regId and tu.branchId = tz.branchId)
   ) and tz.donorBranchId is null and tp.branchid = tz.branchId
   group by tz.branchId
  ) oa
  where tp.planOrder > 0

  -------------------------------------------------------------------------------------------------------

  -- проставляем признак того, что товар исключен, где сумма выходит за рамки планируемой
  update tz
  set tz.excluded = 1
  from #tmpZakaz tz with (nolock)
  join @tblPlanOrder tp on tp.branchid = tz.branchId
  join #tmpRankedProductList c on c.branchId = tz.branchId and tz.autoZakazDataId = c.autoZakazDataId and c.rankedSum > tp.planOrderWOUnexcluded
  where tp.planOrder > 0

  -- сбрасываем заказ на 0 у исключаемых из заказа позиций, чтобы потом их определить как попавшие под ограничение и работать с ними на фронте,
  -- сохраняем сбрасываемое кол-во к заказу
  update o
  set autoZakazExcluded = zakaz
	 ,zakaz = 0
  from #tmpOrder o
  join @tblPlanOrder t on t.branchid = o.branchId
  join #tmpRankedProductList tr
  on tr.branchId = o.branchId and tr.autoZakazDataId = o.autoZakazDataId and tr.rankedSum > t.planOrderWOUnexcluded
  where o.donorBranchId is null and t.planOrder > 0

  drop table #tmpRankedProductList

 -------------------------------------------------------------------------------------------------------
 -- закончили ограничение
 -------------------------------------------------------------------------------------------------------

 end

 -- =============================================================================================
 -- Блок ограничения заказа по сумме конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок проставления у товара признака допустимости исключения из заказа - canBeExcluded начало
 -- =============================================================================================

 -- @important
 -- на данный момент можно исключать позиции, которые не в обязательном бездефектурном наличии асны
 -- не в обязательной матрице созвездия и не в матрице

  if exists(select 1 from #tmpAutoZakazProfile where useRestriction is not null)
  begin

  update o
  set canBeExcluded = 1
  from #tmpOrder o with (nolock)
  join #tmpAutoZakazProfile azp with (nolock) on o.branchId = azp.branchId and azp.useRestriction is not null
  where -- не в обязательной матрице созвездия
	not exists (select 1 from #tmpConstellationMatrixProductList tc where tc.regId = o.regId and tc.branchId = o.branchId) 
	-- не в обязательном бдн асны
	and not exists (select 1 from #tmpASNABDNProductList ta where ta.regId = o.regId and ta.branchId = o.branchId)
	-- не в матрице
	and not exists (select 1 from #tmpMatrixData tu where tu.regId = o.regId and tu.branchId = o.branchId)

  end

 -- =============================================================================================
 -- Блок проставления у товара признака допустимости исключения из заказа - canBeExcluded конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок проставления комментариев к анализируемым товарам начало
 -- =============================================================================================

 /*
   @ipmortant при присваивании другого числового значения комменту необходимо редактировать механизм на фронте, либо ничего не трогать.

   0 - Отсутствуют предложения
   1 - Срок годности
   2 - Минимальный заказ
   3 - Кратность
   4 - Блокировка
   5 - Ограничение заказа
   6 - Неликвид
   7 - Матрица исключения
   8 - Остаток у поставщика
 */

 /*
   @important Последовательность начальную менять не нужно, если не придумается алгоритм лучше

   1. Сначала проставляем матрицы исключения (7), т.к дальнейшие комментарии/проверки будут излишни
   2. Раз товар неликвид (6) то и предложения не нужны.
   3. Отсутствуют предложения (0). Если предложений нет то и проверять дальше бессмысленно
   4. Если стоит блокировка (4) остальные комменты лишние. 
   5. Когда товар попал под ограничение (5) дальше комменты игнорируются.
   6. Дальше комменты (1 - срок годности, 2 - минимальный заказ, 3 - кратность, 8 - остаток поставщика) добавляются друг к другу
 */

   -- список одиночных комментов, которые не участвуют в связке с другими
   declare @tblComments dbo.IntList
   insert into @tblComments ([value]) values(0), (4), (5), (6), (7)

   ------------------------------------------------------------------------------------------------
   -- матрица исключения
   ------------------------------------------------------------------------------------------------

   update tz
   set commentIds = '7'
   from #tmpZakaz tz
   where 
   -- есть товар в матрице исключения
   exists (
    select 1
    from #tmpZakaz tz2
    join #tmpMatrixData tud on tud.outOfAutoOrder = 1 and tz2.drugid = tud.drugid and tz2.formid = tud.formid and tz2.branchId = tud.branchId
    where tz2.parentDrugId = tz.parentDrugId and tz2.parentFormId = tz.parentFormId and tz2.branchId = tz.branchId
   ) and
   -- но не в заказе - значит кроме матрицы исключения заказать нечего
   not exists (select 1 from #tmpOrder t where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId)
   -- родительский товар
   and tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId

   ------------------------------------------------------------------------------------------------
   -- неликвидный товар
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = '6'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId and isnull(tzp.zakazOrig, 0) != 0
   where
   -- родительский товар
   tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId and
   -- нет одиночного коммента
   cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments) and
   -- нет в заказе
   not exists (
    select 1
	from #tmpZakaz t
	join #tmpOrder o1 on t.branchId = o1.branchId and t.drugId = o1.drugId and t.formId = o1.formId
	where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   ) and
   -- обычный неликвидный товар без матрицы, маркетингов: асны, созвездия
   (
    -- неликвид
    isnull(tz.noMoveDay, 0) >= (select noMoveDaysMax from #tmpAutoZakazProfile tap where tap.branchId = tz.branchId) 
    -- не в матрице
    and not exists (
	 select 1 
	 from #tmpZakaz t
	 join #tmpMatrixData tu on tu.drugId = t.drugid and tu.formId = t.formid and tu.branchId = t.branchid
	 where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
     ) 
     -- не в созвездии
     and not exists (
	 select 1 
	 from #tmpZakaz t
	 join #tmpConstellationMatrixProductList tpl on t.drugId = tpl.drugId and t.formId = tpl.formId and t.branchId = tpl.branchId
	 where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
      ) 
      -- не в АСНА
      and not exists (
	 select 1 
	 from #tmpZakaz t
	 join #tmpASNABDNProductList tam on tam.drugId = t.drugId and tam.formId = t.formId and tam.branchId = t.branchId
	 where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
      )
   ) or
   -- неликвидный товар из созвездия, с выполненым планом
   (
    -- в созвездии
    exists (
	 select 1 
	 from #tmpZakaz t
	 join #tmpConstellationMatrixProductList tcpl on tcpl.branchId = t.branchId and tcpl.drugId = t.drugId and tcpl.formId = t.formId
	 where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
     ) 
     -- неликвидные товары созвездия с выполненым планом
     and exists (
	 select 1
	 from #tmpZakaz t
	 join #tmpConstellationMatrixCompleteList tcpl on tcpl.branchId = t.branchId and tcpl.drugId = t.drugId and tcpl.formId = t.formId
	 where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
     )
   ) or
   -- неликвидный товар из АСНА с выполненым планом
   (
	-- превышение дней без продаж
	isnull(tz.noMoveDay, 0) >= (select noMoveDaysMax from #tmpAutoZakazProfile tap where tap.branchId = tz.branchId)
	-- в АСНА
	and exists (
	 select 1 
	 from #tmpZakaz t
	 join #tmpASNABDNProductList tam on tam.drugId = t.drugId and tam.formId = t.formId and tam.branchId = t.branchId
	 where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
	)
	-- план выполнен
	and exists (
	 select 1
	 from #tmpZakaz t
	 join #tmpASNABDNProductList tam 
	 on tam.drugId = t.drugId and tam.formId = t.formId and tam.branchId = t.branchId and t.ost + t.tovInAWay >= tam.minQnt and t.zakazOrig < tam.minQnt
	 where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
	)
   ) or
   -- неликвидный товар из матрицы с выполненым планом
   (
    -- превышение дней без продаж
    isnull(tz.noMoveDay, 0) >= (select noMoveDaysMax from #tmpAutoZakazProfile tap where tap.branchId = tz.branchId)
    -- в матрице
    and exists (
	 select 1 
	 from #tmpZakaz t
	 join #tmpMatrixData tu on tu.drugId = t.drugid and tu.formId = t.formid and tu.branchId = t.branchid
	 where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
    )
    -- план выполнен
    and exists (
     select 1
	 from #tmpZakaz t
     	 join #tmpMatrixData tu 
	 on tu.drugId = t.drugid and tu.formId = t.formid and tu.branchId = t.branchid and t.ost + t.tovInAWay >= tu.minOst and t.zakazOrig < tu.minOst
     	 where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
    )
   )

   ------------------------------------------------------------------------------------------------
   -- отсутствует предложение
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = '0'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock) 
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId and isnull(tzp.zakazOrig, 0) != 0
   where 
   -- нет одиночного коммента
   cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments) and
   -- нет предложений в прайс-листе
   not exists (
    select 1
    from #tmpZakaz t
    join #tmpPriceList tpl on tpl.drugId = t.drugId and tpl.formId = t.formId
    join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
    where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   )
   -- товар родитель
   and tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId

   ------------------------------------------------------------------------------------------------
   -- блокировка
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = '4'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId and isnull(tzp.zakazOrig, 0) != 0
   where tz.complete = 0 
   -- не стоит уже одиночный коммент
   and cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments)
   -- товар родитель
   and tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId
   -- есть предложения
   and exists (
    select 1
    from #tmpZakaz t
    join #tmpPriceList tpl on t.drugId = tpl.drugId and t.formId = tpl.formId
    join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
    where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   )
   -- нет предложений без блокировки
   and not exists (
    select 1
    from #tmpZakaz t
    join #tmpPriceList tpl on t.drugId = tpl.drugId and t.formId = tpl.formId
    join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
    where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId and tpl.[block] != '1'
   )

   ------------------------------------------------------------------------------------------------
   -- ограничение суммы заказа
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = '5'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId and isnull(tzp.zakazOrig, 0) != 0
   where 
   -- есть товар с признаком исключения
   exists (
    select 1 
    from #tmpZakaz t 
    where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.excluded = 1 
   )
   -- нет одиночного коммента
   and cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments) -- todo подумать
   -- товар родитель
   and tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId

   ------------------------------------------------------------------------------------------------
   -- срок годности
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = '1'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId and isnull(tzp.zakazOrig, 0) != 0
   where tz.complete = 0 and 
   -- нет одиночного коммента
   cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments) and
   -- есть предложения
   exists (
    select 1
    from #tmpZakaz t
    join #tmpPriceList tpl on t.drugId = tpl.drugId and t.formId = tpl.formId
    join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
    where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   ) and
   -- нет предложений с нормальным сроком годности
   not exists (
    select 1
    from #tmpZakaz t
    join #tmpPriceList tpl on t.drugId = tpl.drugId and t.formId = tpl.formId
    join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
    left join #tmpSrokG s with (nolock) on s.branchId = tz.branchId
    where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId and datediff(month, @curDate, tpl.srokG) > s.srokGInMonth
   ) and
   -- товар родитель
   tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId

   ------------------------------------------------------------------------------------------------
   -- минимальный заказ
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '2'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId and isnull(tzp.zakazOrig, 0) != 0
   where tz.complete = 0 and 
   -- не стоит одиночный коммент
   cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments) and
   -- товар родитель
   tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId and
   -- есть предложения
   exists (
    	select 1
	from #tmpZakaz t
	join #tmpPriceList tpl on tpl.drugId = t.drugId and tpl.formId = t.formId
	join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
	where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   )
   -- нет предложений с нормальной минимальной ценой
   and not exists (
    	select 1
	from #tmpZakaz t
	join #tmpPriceList tpl on tpl.drugId = t.drugId and tpl.formId = t.formId and t.zakazOrig >= tpl.minZakaz
	join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
	where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   )

   ------------------------------------------------------------------------------------------------
   -- кратность
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '3'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId and isnull(tzp.zakazOrig, 0) != 0
   where tz.complete = 0 and 
   -- есть предложения
   exists (
    	select 1
	from #tmpZakaz t
	join #tmpPriceList tpl on tpl.drugId = t.drugId and tpl.formId = t.formId
	join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
	where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   )
   -- нет предложений с нормальной минимальной ценой
   and not exists (
    	select 1
	from #tmpZakaz t
	join #tmpPriceList tpl on tpl.drugId = t.drugId and tpl.formId = t.formId and t.zakazOrig % tpl.ratio = 0
	join #tmpDistrPriority tdp on tdp.distrId = tpl.distrId and tdp.branchId = t.branchId
	where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   ) and
   -- не стоит одиночный коммент
   (
     commentIds is null or ',' like commentIds or
     (',' not like commentIds and cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments))
   ) and
   -- товар родитель
   tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId

   ------------------------------------------------------------------------------------------------
   -- остаток у поставщика
   ------------------------------------------------------------------------------------------------

   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '8'
   from #tmpZakaz tz
   where 
   -- todo если будет что то не так добавить проверку на отсутствие предложений с остатком большим чем потребность
   -- существуют предложения с остатком меньше потребности
   exists (
    	select 1
	from #tmpZakaz t
    	join #tmpPriceList tpl on tpl.drugId = t.drugId and tpl.formId = t.formId and tpl.qntOst < t.zakazOrig and tpl.donorBranchId is null
	join #tmpDistrPriority tdp on tdp.branchId = tz.branchId and tdp.distrId = tpl.distrId
	where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   )
   -- товар есть в заказе
   and exists (
    	select 1
	from #tmpOrder t
	where t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId and t.branchId = tz.branchId
   )
   -- суммарный заказ меньше потребности, значит чего то не хватило
   and (
    	select sum(t.zakaz) 
	from #tmpOrder t
	join #tmpZakaz t2 on t.branchId = t2.branchId and t.drugId = t2.drugId and t.formId = t2.formId
	where t2.parentDrugId = tz.parentDrugId and t2.parentFormId = tz.parentFormId and t2.branchId = tz.branchId
   ) < tz.zakazOrig and
   -- уже не стоит одиночный коммент
   (
     commentIds is null or ',' like commentIds or
     (',' not like commentIds and cast(isnull(commentIds, -1) as int) not in (select [value] from @tblComments))
   )
   -- родительский товар
   and tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId

   ------------------------------------------------------------------------------------------------
   -- проставление комментов к товарам, которые могли бы попасть в ограничение если бы попали в заказ
   ------------------------------------------------------------------------------------------------
   
   -- если есть товар с ограничением
   if exists (select 1 from #tmpZakaz where excluded = 1)
   begin

   -- строка, с которой начинается ограничение
   declare @tblEff table (
    branchId int, -- идентификатор филиала
    k_eff_num int -- номер строки
   )

   -- создаем полную копию #tmpZakaz с нумерацией по коэффициенту эффективности
   select top 0 * into #tmpZakazRanked from #tmpZakaz

   -- добавляем столбец с нумерацией
   alter table #tmpZakazRanked add k_eff_num int

   -- заполняем данные с нумерацией
   insert into #tmpZakazRanked
   select *, row_number() over (partition by branchId order by keff desc, drugid asc, formid asc)
   from #tmpZakaz

   -- определяем строку с которой начинается ограничение
   insert into @tblEff(branchId, k_eff_num)
   select tb.branchId, oa.k_eff_num
   from #tmpBranch tb
   outer apply (
    	select top 1 tzr.k_eff_num
	from #tmpZakazRanked tzr
	where tzr.branchId = tb.branchId and tzr.excluded = 1
   ) oa

   -- обновляем комменты по тем товарам, которые не попали в заказ по каким то причинам кроме ограничения, но если бы попали то были бы в ограничении
   update tz
   set commentIds = iif(isnull(tzr.commentIds, '') = '', '', tzr.commentIds + ',') + '5'
   from #tmpZakazRanked tzr
   join #tmpZakaz tz 
   on tz.branchId = tzr.branchId and tz.parentDrugId = tzr.parentDrugId and tz.parentFormId = tzr.parentFormId and tz.commentIds is not null
   join #tmpBranch tb on tz.branchId = tb.branchId and isnull(tb.restrictionSum, 0) > 0
   join @tblEff te on te.branchId = tz.branchId and te.k_eff_num is not null
   where tzr.k_eff_num >= te.k_eff_num 
	 and tzr.commentIds is not null 
	 and '5' not like tzr.commentIds 
	 and '6' not like tzr.commentIds
	 and '8' not like tzr.commentIds
	 -- не в матрице
	 and not exists (
	  select 1 
	  from #tmpZakaz t
	  join #tmpMatrixData tu on tu.drugId = t.drugid and tu.formId = t.formid and tu.branchId = t.branchid
	  where t.parentDrugId = tz.parentDrugId 
	    and t.parentFormId = tz.parentFormId 
	    and t.branchId = tz.branchId
	 ) 
	 -- не в созвездии
	 and not exists (
	  select 1 
	  from #tmpZakaz t
	  join #tmpConstellationMatrixProductList tpl 
	  on t.drugId = tpl.drugId and t.formId = tpl.formId and t.branchId = tpl.branchId
	  where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
	 ) 
	 -- не в АСНА
	 and not exists (
	  select 1 
	  from #tmpZakaz t
	  join #tmpASNABDNProductList tam 
	  on tam.drugId = t.drugId and tam.formId = t.formId and tam.branchId = t.branchId
	  where t.branchId = tz.branchId and t.parentDrugId = tz.parentDrugId and t.parentFormId = tz.parentFormId
	 )

   drop table #tmpZakazRanked

   end

 ------------------------------------------------------------------------------------------------

  -- закрываем коммент в квадратные скобки а-ля массив
  update tz
  set tz.commentIds = '[' + tz.commentIds + ']'
  from #tmpZakaz tz
  where tz.commentIds is not null

 -- =============================================================================================
 -- Блок проставления комментариев к анализируемым товарам конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок заполнения дополнительных данных начало
 -- =============================================================================================

  -- если табличка - #tmpExtraData существует - заполняем
  if OBJECT_ID(N'tempDB..#tmpExtraData', N'U') is not null
  begin

   -- сохраняем объект с предложениями, рекомендованными поставщиками по товару
   insert into #tmpExtraData(AutoZakazDataId, OffersAndSuppliers)
   select tz.autoZakazDataId, '{"offers":' + isnull(oa.offers, '[]') + ', "recommended_suppliers":' + isnull(oa2.recommended_suppliers, '[]') + '}'
   from #tmpZakaz tz
   ---------------предложения---------------
   outer apply (
    select tz2.autoZakazDataId 		   as auto_zakaz_data_id
		  ,tp.regId		   as reg_id
		  ,tp.drugId		   as drug_id
		  ,tp.formId		   as form_id
		  ,tp.fabrId		   as fabr_id
		  ,tp.distrId		   as distr_id_web
		  ,tp.priceId		   as distr_price_id
		  ,tp.price		   as distr_price
		  ,tp.qntOst		   as distr_ost
		  ,tp.minZakaz		   as distr_min_zakaz
		  ,tp.ratio		   as distr_ratio
		  ,tp.distr		   as distr_name
		  ,tp.priceFabr		   as distr_price_fabr
		  ,tz2.kEff		   as k_eff
		  ,vr.Drug		   as drug_name
		  ,vr.Form		   as form_name
		  ,vr.Fabr		   as fabr_name
	from #tmpZakaz tz2
	join #tmpPriceList tp on tp.drugId = tz2.drugId and tp.formId = tz2.formId
	join Megapress.dbo.vRegistry vr on vr.REGID = tp.regId
	join #tmpDistrPriority td on td.distrId = tp.distrId and td.branchId = tz2.branchId
	left join #tmpSrokG s on s.branchId = tz2.branchId
	left join #tmpAutoZakazProfile tazp with (nolock) on tazp.branchId = tz2.branchId
	where tz2.parentDrugId = tz.parentDrugId 
	  and tz2.parentFormId = tz.parentFormId 
	  and tz2.branchId = tz.branchId 
	  -- блокировка
	  and tp.block != '1'
	  -- срок годности
	  -- and (datediff(month, @curDate, tp.srokG) >= s.srokGInMonth or @srokG = '0')
	  -- не перемещение
	  and tp.donorBranchId is null
	  -- учет уценки
	  and (
		(
		  tAZP.excludeDiscounted = '1' and 
		  tp.nacenk = '0'
		) 
		or 
		tAZP.excludeDiscounted = '0'
	  )
	  -- учет матричных поставщиков
	  and (
		-- не матричный
		tp.matrixTitleId is null 
		or
		(
		  -- если матричный
		  tp.matrixTitleId is not null 
		  and
		  -- то смотрим по матричным поставщикам
		  exists (
			   select 1 
			   from #tmpMatrixDistr tmd 
			   where tmd.matrixTitleId = tp.matrixTitleId and tmd.branchId = tz2.branchId and tmd.distrId = tp.distrId
		  )
	        )
	)
	order by tp.price asc
	for json path
   ) oa (offers)
   ---------------рекомендуемые-поставщики---------------
   outer apply (
	select 	   tmd.branchId		as branch_id
		  ,tmd.regId		as reg_id
		  ,tmd.drugId		as drug_id
		  ,tmd.formId		as form_id
		  ,tmd.distrId		as distr_id
		  ,tz2.parentDrugId 	as parent_drug_id
		  ,tz2.parentFormId	as parent_form_id
	from #tmpZakaz tz2
	join #tmpMarketingDistrPriority tmd on tmd.branchId = tz2.branchId and tmd.drugId = tz2.drugId and tmd.formId = tz2.formId
	where tz2.branchId = tz.branchId and tz2.parentDrugId = tz.parentDrugId and tz2.parentFormId = tz.parentFormId
	for json path
   ) oa2 (recommended_suppliers)
   where 
	 -- комментарии есть
	 tz.commentIds is not null 
	 -- заказ не полный
	 and tz.zakaz > 0 
		 -- есть предложения
	 and oa.offers is not null
		 -- не неликвид
	 and tz.commentIds != '[6]'
	 -- не отсутствуют предложения
	 and '0' not like tz.commentIds

   end

 -- =============================================================================================
 -- Блок заполнения дополнительных данных конец
 ------------------------------------------------------------------------------------------------

 ------------------------------------------------------------------------------------------------
 -- Блок проставления комментариев к заказу начало
 -- =============================================================================================

  -- отсутствуют настройки поставщиков
  ;
 with cteDistrCount as (select branchId, count(distrId) countDistrId
                        from #tmpDistrPriority
                        where priority is not null
                        group by branchId)
 update tb
 set tb.comment = iif(isnull(tb.comment, '') = '', '', tb.comment + ', ') + 'отсутствуют настройки поставщиков'
 from #tmpBranch tb
 left join cteDistrCount dc on dc.branchId = tb.branchId
 where isnull(dc.countDistrId, 0) = 0

-- отсутствуют доноры с расчитанным избытком
 ;
 with cteDonorCount as (select recepientBranchId branchId, count(donorBranchId) countDonor
                        from #tmpMove
                        where autoZakazTitleId is not null
                        group by recepientBranchId)
 update tb
 set tb.comment = iif(isnull(tb.comment, '') = '', '', tb.comment + ', ') + 'отсутствуют доноры с расчитанным избытком'
 from #tmpBranch tb
 left join cteDonorCount dc on dc.branchId = tb.branchId
 where isnull(dc.countDonor, 0) = 0 and dc.branchId is not null

-- отсутствуют приоритеты производителей
 if not exists(select 1 from #tmpFabrPriority where priority > 0)
  update #tmpBranch
  set comment = iif(isnull(comment, '') = '', '', comment + ', ') + 'отсутствуют приоритеты производителей'

-- не загружен прайс-лист
 if not exists(select 1 from #tmpPriceList)
  update #tmpBranch
  set comment = iif(isnull(comment, '') = '', '', comment + ', ') + 'не загружен прайс-лист'

 -- =============================================================================================
 -- Блок проставления комментариев к заказу конец
 ------------------------------------------------------------------------------------------------

 drop table #tmpDistr
 drop table #tmpDouble
 drop table #tmpMatrixDistr
 drop table #tmpMove
 drop table #tmpMatrixData
 drop table #tmpZakazParent
 drop table #tmpPriceList
 drop table #tmpPriceListIdList
 drop table #tmpFabrPriority
 drop table #tmpMarketingDistrPriority
 drop table #tmpDoublesForPriority
 drop table #tmpAutoZakazProfile
 drop table #tmpDonorSrokG
 drop table #tmpASNABDNProductList
 drop table #tmpConstellationMatrixProductList
 drop table #tmpConstellationMatrixCompleteList
END

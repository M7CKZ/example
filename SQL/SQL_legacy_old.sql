USE [Miracle]
GO
/****** Object:  StoredProcedure [dbo].[KW_order_core_v9]    Script Date: 18.01.2023 16:22:39 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		*Секрет*
-- Create date: 09.10.2019
-- Description:	Заполнение заказа (#tmpOrder) в зависимости от параметров
--	  23.04.2020 - *Секрет*, блокировка по parentId, исправления дублей на parentId
--    20.05.2021 - *Секрет*: учет маркетинговых товаров
--    30.11.2021 - (v5) *Секрет*: ограничение суммы заказа
-- Список процедур откуда вызывается данная процедура
-- AutoZakazCreateOrder
-- KW_703_4
-- KW_110_6
-- KW_114_3
--
-- Список входящих таблиц
-- #tmpBranch -- список филиалов
-- #tmpSrokG -- сроки годности по филиалам
-- #tmpZakaz или @docList и @parentDF_or_regId = 1 для заполнения #tmpZakaz -- список товаров с потребностью
-- #tmpDistrPriority или @distr = 1 -- Поставщики по которым мы размещаем товары
-- =============================================
ALTER PROCEDURE [dbo].[KW_order_core_v9]
 @customerId int, -- идентификатор контрагента
 @historId int, -- идентификатор прайс-листа
 @docList dbo.IntList readonly, -- список документов для размещени.
 @block char(1), -- Блокировка. 1 - учитывается, 0 - не учитывается.
 @double char(1), -- Дубли. 1 - учитывается, 0 - не учитывается.
 @priority char(1), -- Приоритет поставщиков. 1 - учитывается, 0 - не учитывается.  Сделано
 @donor char(1), -- Доноры. 1 - учитывается, 0 - не учитывается.
 @srokG char(1), -- Срок годности. 1 - учитывается, 0 - не учитывается.
 @matrix char(1), -- Матрицы. 1 - учитывается, 0 - не учитывается.
 @parentDF_or_regId char(1), -- делаем размещение по parentDrug и parentForm или regId. 1 - parentDrug и parentForm, 2 - regId.
 @reorder char(1), -- Перезаказа. 1 - учитывается, 0 - не учитывается.
 @type_update char(1), -- тип обновления. 1 - по поставщику, 2 - по минимальным ценам.
 @distr char(1), -- Получать список поставщиков с приоритетами. 0 - нет, 1 - свой.
 @marketing char(1) -- Учитывать маркетинговые товары. 0 - нет, 1 - да.
AS
BEGIN

 set nocount on;
 set transaction isolation level read uncommitted;

 declare
  @curDate datetime = getDate(), -- текущая дата
  @defSrokGInMonth smallint = 6, -- остаточный срок годности в месяцах по умолчанию
  @defSrokGInDays smallint = 180, -- остаточный срок годности в днях по умолчанию
  @regIdList dbo.IntList, -- список товаров дял получения прайс-листа

  @parentCustomerId int = Miracle.dbo.GetParentCustomerId(@customerId), -- id владельца
  @parentCustomerTime datetime, -- текущие дата и время владельца
  @parentCustomerDate date, -- текущая дата владельца
  @defaultReserveDays int = 20

-- получаем текущие дата и время владельца
 select @parentCustomerTime = todatetimeoffset(@curDate, coalesce(ci.timeZone, '+03:00'))
 from Miracle.dbo.Customer cu with (nolock)
 left join Miracle.dbo.City ci with (nolock) on ci.CityID = cu.CityID
 where cu.CustomerID = @parentCustomerId

-- выделяем только дату от даты и времени владельца
 select @parentCustomerDate = convert(date, @parentCustomerTime)

 create table #tmpAutoZakazProfile (
  branchId int,
  noMoveDaysMax int, -- кол-во дней по профилю автозаказа, для учета товара неликвидным
  useRestriction bit -- использовать ограничение
 )

-- сводный прайс-лист
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
  ordered bit default 0      -- признак заказанной позиции
 )

-- для дублей родительские товары и суммарные характеристики
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
  complete bit default 0-- признак завершенного размещения
 )

-- дубли
 create table #tmpDouble (
  doubleId int,
  parentDoubleId int,
  drugId int,
  formId int
 )

-- перемещения
 create table #tmpMove (
  recepientBranchId int,
  donorBranchId int,
  autoZakazTitleId int
 )

--таблица с матрицами филиалами и категориями
 create table #tmpMatrixToBranch (
  matrixTitleId int,
  branchId int,
  categoryName varchar(150),
  categoryId int,
  [priority] smallint,
  createDate datetime,
  outOfAutoOrder bit --  признак матрицы исключения
 )

-- таблица товаров в матрицах без учёта производителей
 create table #tmpTopRegId (
  matrixTitleId int,
  matrixDataId int,
  topRegId int,
  fabrType char(1),
  branchId int,
  minOst int,
  porogZakaz numeric(15, 5),
  [priority] smallint,
  createDate datetime,
  outOfAutoOrder bit --  признак матрицы исключения
 )

-- таблица товаров в матрицах c учётом производителей
 create table #tmpMatrixData (
  matrixTitleId int,
  drugId int,
  formId int,
  fabrId int,
  branchId int,
  minOst int,
  porogZakaz numeric(15, 5),
  createDate datetime,
  [priority] smallint,
  outOfAutoOrder bit --  признак матрицы исключения
 )

-- уникальные regId отсортированные по приоритету
 create table #tmpUnicDrugIdFormId (
  matrixTitleId int,
  drugId int,
  formId int,
  fabrId int,
  branchId int,
  minOst int,
  porogZakaz numeric(15, 5),
  createDate datetime,
  [priority] smallint,
  outOfAutoOrder bit --  признак матрицы исключения
 )

-- поставщики для матриц
 create table #tmpMatrixDistr (
  matrixTitleId int,
  branchId int,
  distrId int
 )

 -- список товаров маркетинга АСНА (БДН)
 create table #tmpASNAMarketing (
  branchId int,
  minQnt numeric(15, 5), -- план штук
  regId int,
  drugId int,
  formId int,
  nnt int
 )

 -- список товаров созвездия (обязательная матрица)
 create table #tmpConstellationProductList (
  branchId int,
  regId int,
  drugId int,
  formId int,
  minOst int
 )

 -- список неликвидных товаров из созвездия с выполненым планом
 create table #tmpConstellationCompleteList (
  branchId int,
  drugId int,
  formId int,
  parentDrugId int,
  parentFormId int,
  qnt int
 )

 create table #tmpPriceListIdList (
  priceId bigint,
  pNumber int,
  branchId int
 )

 create table #tmpPlanOrder (
  branchid int,
  planOrder numeric(15, 5)
 )

 -- приоритеты производителей
 create table #tmpFabrPriority (
  regId int,
  priority int,
  parentDrugId int,
  parentFormId int
 )

 -- поставщики
 create table #tmpDistr(
  distrId int,
  sql2DistrId int
 )

 -- проценты превышения для игнора поставщика по филиалам
 create table #tmpMarketingIgnorePercent (
  branchId int,				-- филиал
  [percent] numeric (15, 5)	-- процент превышения
 )

 -- приоритеты поставщиков маркетинговых товаров
 create table #tmpMarketingDistrPriority (
  [percent] numeric (15, 5), -- процент превышения минимальной цены, для игнора поставщика
  distrId int,			   -- идентификатор поставщика
  branchId int,			   -- идентификатор филиала
  regId int,				   -- идентификатор товара, т.к у каждого товара свои приоритеты
  [priority] int,			   -- приоритет
  drugId int,
  formId int
 )

 -- список дублей, для определения приоритетов производителей, затем отсюда добавляются в #tmpDoubles, если нужен учет дублей
 create table #tmpDoublesForPriority (
  id int default -1,
  parentId int default 0,
  parentDrugId int,
  parentFormId int,
  drugId int,
  formId int
 )

 -- остаточные сроки годности по филиалам донорам
 create table #tmpDonorSrokG (
  branchId int,         -- идентификатор филиала
  srokGInDayForMove int -- остаточный срок годности в днях для перемещений
 )

 insert into #tmpAutoZakazProfile (branchId)
 select branchId from #tmpBranch with (nolock)

 update #tmpAutoZakazProfile
 set noMoveDaysMax = azp2.noMoveDayCount,
  useRestriction = azp2.useRestriction
 from Miracle.dbo.AutoZakazProfileToBranch azptb with (nolock)
 left join Miracle.dbo.AutoZakazProfile azp2 with (nolock) on azp2.autoZakazProfileId = azptb.autoZakazProfileId and azp2.isDefault != '1' and azp2.disable = '0'
 where azptb.branchId = #tmpAutoZakazProfile.branchId and azptb.disable = '0'

 update #tmpAutoZakazProfile
 set noMoveDaysMax = azp.noMoveDayCount,
  useRestriction = azp.useRestriction
 from Miracle.dbo.AutoZakazProfile azp with (nolock)
 where azp.customerId = @customerId and azp.disable = '0' and azp.isDefault = '1' and noMoveDaysMax is null
 option (optimize for unknown)

 -- родительские дубли
 insert into #tmpDoublesForPriority(id, parentDrugId, parentFormId, drugId, formId)
 select dc.DoubleCustomerId, dc.drugid, dc.formid, dc.drugid, dc.formid
 from Miracle.dbo.DoubleCustomer dc with (nolock)
 where dc.ParentDoubleCustomerId = dc.DoubleCustomerId and [disable] = '0' and dc.parentCustomerId = @parentCustomerId

-- дочерние дубли
 insert into #tmpDoublesForPriority(parentId, parentDrugId, parentFormId, drugId, formId)
 select td.id, td.parentDrugId, td.parentFormId, dc.drugId, dc.formId
 from #tmpDoublesForPriority td with (nolock)
 left join Miracle.dbo.DoubleCustomer dc with (nolock) on dc.ParentDoubleCustomerId = td.id and dc.DoubleCustomerId != dc.ParentDoubleCustomerId
 where dc.[disable] = '0'

-- добавление в список приоритетов товаров, у которых нет дубля
 insert into #tmpFabrPriority(regId, priority, parentDrugId, parentFormId)
 select vr.regid, ap.priority, ap.drugId, ap.formId
 from AutoZakazFabrPriority ap with (nolock)
 join Megapress.dbo.Registry vr with (nolock) on ap.drugId = vr.drugid and ap.formId = vr.formid and ap.fabrId = vr.fabrId
 where not exists (select 1 from #tmpDoublesForPriority tdp where tdp.parentDrugId = ap.drugId and tdp.parentFormId = ap.formId)
  and ap.usingInAutoZakaz = '1' and parentCustomerId = @customerId

-- добавление в список приоритетов дублей
 insert into #tmpFabrPriority(regId, priority, parentDrugId, parentFormId)
 select vr.regid, afp.priority, tdp.parentDrugId, tdp.parentFormId
 from #tmpDoublesForPriority tdp with (nolock)
 left join AutoZakazFabrPriority afp with (nolock) on tdp.parentDrugId = afp.drugId and tdp.parentFormId = afp.formId and afp.usingInAutoZakaz = '1'
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

-- Дубли
 if @double = '1'
  begin
   insert into #tmpDouble(doubleId, parentDoubleId, drugId, formId)
   select id, parentId, drugId, formid from #tmpDoublesForPriority with (nolock)
  end

-- Потребность для заказа
 if @parentDF_or_regId = '1'
  begin

   -- получаем документы автозаказа
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
    --left join #tmpUnicDrugIdFormId udf with (nolock) on udf.drugId = zd.drugId and udf.formId = zd.formId
   where (isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix) > 0 /*or udf.matrixTitleId > 0 */or exists (
    select 1 from #tmpDouble td with (nolock) where td.drugId = zd.drugId and td.formId = zd.formId
    )) and not exists (
    select 1
    from Miracle.dbo.AutoZakazNoAssort na with (nolock)
    where na.branchId = zt.branchId and na.drugId = zd.drugId and na.formId = zd.formId and na.[disable] = '0'
    ) and zd.autoZakazTitleId in (select value from @docList)
   option (optimize for unknown)
   /*
   from @docList dl
   join Miracle.dbo.AutoZakazData zd with (nolock) on dl.[value] = zd.autoZakazTitleId
   left join Miracle.dbo.AutoZakazTitle zt with (nolock) on zt.autoZakazTitleId = zd.autoZakazTitleId
   left join Miracle.dbo.AutoZakazNoAssort na with (nolock)
   on na.branchId = zt.branchId and na.drugId = zd.drugId and na.formId = zd.formId and na.[disable] = '0'
   left join #tmpUnicDrugIdFormId udf with (nolock) on udf.drugId = zd.drugId and udf.formId = zd.formId
   left join #tmpDouble td with (nolock) on td.drugId = zd.drugId and td.formId = zd.formId
   where na.autoZakazNoAssortId is null and (zd.zakazToOrder > 0 or udf.matrixTitleId > 0 or td.doubleId is not null)
   option (optimize for unknown)
   */

   insert into @regIdList (
    [value]
   )
   select distinct r.REGID
   from #tmpDouble td with (nolock)
   left join #tmpZakaz tz with (nolock) on tz.drugId = td.drugId and tz.formId = td.formId
   left join Megapress.dbo.Registry r with (nolock)
   on r.DRUGID = td.drugId and r.FORMID = td.formId and r.FLAG = '0'
   where tz.drugId is null

   insert into @regIdList (
    [value]
   )
   select r.REGID
   from #tmpZakaz tz with (nolock)
   join Megapress.dbo.Registry r with (nolock) on r.DRUGID = tz.drugId and r.FORMID = tz.formId and r.FLAG = '0'
   group by r.REGID

   -- проставляем родительский товар (название, форма), если нет дублей или это родительский товар, то parentId = Id
   update tz
   set parentDrugId = iif(tdp.drugId is null, tz.drugId, tdp.drugId),
    parentFormId = iif(tdp.formId is null, tz.formId, tdp.formId)
   from #tmpZakaz tz with (nolock)
   left join #tmpDouble td with (nolock) on td.drugId = tz.drugId and td.formId = tz.formId and td.parentDoubleId != 0
   left join #tmpDouble tdp with (nolock) on tdp.doubleId = td.parentDoubleId

   -- для родительских позиций по дублям добавляем показатели на основе которых будет происходить размещение
   -- (больше не суммируем, все данные для дубля считаются в расчетах потребности)
   insert into #tmpZakazParent (
    parentDrugId, parentFormId, zakaz, speedMax, threshold1, threshold2, ost, tovInAWay, branchId
   )
   select tz.parentDrugId,
    tz.parentFormId,
    tz.zakaz,
    tz.speedMax,
    tz.threshold1,
    tz.threshold2,
    tz.ost,
    tz.tovInAWay,
    tz.branchId
   from #tmpZakaz tz with (nolock)
   where tz.drugId = tz.parentDrugId and tz.formId = tz.parentFormId
  end
 else
  if @parentDF_or_regId = '2'
   begin
    insert into @regIdList (
     [value]
    )
    select tz.regId
    from #tmpZakaz tz with (nolock)
    group by tz.regid

    if @type_update = '1'
     begin
      -- для родительских позиций по дублям суммируем показатели на основе которых будет происходить размещение
      insert into #tmpZakazParent (
       parentRegId, parentDistrId, zakaz, speedMax, threshold1, threshold2, ost, tovInAWay, branchId
      )
      select tz.regId,
       tz.distrId,
       tz.zakaz,
       tz.speedMax,
       tz.threshold1,
       tz.threshold2,
       tz.ost,
       tz.tovInAWay,
       tz.branchId
      from #tmpZakaz tz with (nolock)
     end
    else
     begin
      -- для родительских позиций по дублям добавляем показатели на основе которых будет происходить размещение
      -- (больше не суммируем, все данные для дубля считаются в расчетах потребности)
      -- todo проверить, скорректировать, не ясный момент.
      insert into #tmpZakazParent (
       parentRegId, zakaz, speedMax, threshold1, threshold2, ost, tovInAWay, branchId
      )
      select tz.regId,
       sum(tz.zakaz),
       sum(tz.speedMax),
       sum(tz.threshold1),
       sum(tz.threshold2),
       sum(tz.ost),
       sum(tz.tovInAWay),
       tz.branchId
      from #tmpZakaz tz with (nolock)
      group by tz.regId, tz.branchId
     end
   end

 update #tmpZakazParent
 set zakazOrig = zakaz

-- Получаем нужные товары для размещения
 insert into #tmpPriceList(
  regId, drugId, formId, fabrId, distrId, sql2DistrId, priceId, price, qntOst, minZakaz, srokG, ratio, distr, priceFabr
 )
  exec Miracle.dbo.AutoZakazGetSvodPriceByRegId_v3 @customerId, @historId, @regIdList

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

   --update tp set
   -- tp.[block] = case when bz.Flag = '1' OR bzd.[Disable] = '1'  then '0' else '1' end
   --from #tmpPriceList tp
   --left join Miracle.dbo.BlockZak bz on bz.RegId = tp.regId and bz.CustomerID = @customerId and bz.[Disable] = '0'
   --left join Miracle.dbo.BlockZakDistr bzd on bzd.BlockZakID = bz.BlockZakID and bzd.DistrID = tp.distrId
   --option (optimize for unknown)
  end
 else
  -- Иначе проставляем нулями
  update #tmpPriceList
  set [block] = '0'

-- Получаем доноров
 if @donor = '1'
  begin
   /*
    -- получаем связку реципиентов и доноров
    insert into #tmpMove (
     recepientBranchId, donorBranchId
    )
    select tb.branchId, amd.branchId
    from #tmpBranch tb with (nolock)
    join Miracle.dbo.AutoZakazMoveSettings ams with (nolock) on tb.branchId = ams.branchId
    join Miracle.dbo.AutoZakazMoveDonor amd with (nolock)
    on amd.autoZakazMoveSettingsId = ams.autoZakazMoveSettingsId and amd.[disable] = '0'
    */
   -- получаем связку реципиентов и доноров
   insert into #tmpMove (
    recepientBranchId, donorBranchId, autoZakazTitleId
   )
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

   --option (optimize for unknown)

   -- получаем "прайс-лист" от доноров по последнему рассчитанному автозаказу но не старше предыдущего дня от дня заказа

   -- todo 38%
   /*
   ;
   with cte_azt as (
    select azt.autoZakazTitleId,
     azt.branchId,
     row_number() over (partition by azt.branchId order by azt.createDate desc) rowNum
    from Miracle.dbo.AutoZakazTitle azt with (nolock)
    join #tmpMove tm with (nolock) on tm.donorBranchId = azt.branchId
    where azt.createDate > DATEADD(d, -1, cast(@curDate as date))
   )
   */

   -- todo 19%
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
   from #tmpMove tm with (nolock)
    --join cte_azt ca with (nolock) on tm.donorBranchId = ca.branchId and ca.rowNum = 1
   join Miracle.dbo.AutoZakazData azd with (nolock)
   on azd.autoZakazTitleId = tm.autoZakazTitleId and isnull(azd.excess, 0) > 0
   join Megapress.dbo.Registry r with (nolock) on r.DRUGID = azd.drugId and r.FORMID = azd.formId
   join Miracle.dbo.NaklData nd with (nolock)
   on nd.branchId = tm.donorBranchId and nd.[disable] = '0' and nd.uQntOst > 0.001 and nd.RegID = r.REGID
   left join Miracle.dbo.NaklData nd2 with (nolock) on nd.FirstNaklDataID = nd2.NaklDataID
  end

 -- todo проверить все внимательнее, много обращений в dbo.Registry
 if @matrix = '1'
  begin
   -- Получение матриц
   insert into #tmpMatrixToBranch (
    matrixTitleId, branchId, [priority], createDate, outOfAutoOrder
   )
   select mt.matrixTitleId, tb.branchId, mt.[priority], mt.createDate, isnull(mt.outOfAutoOrder, 0)
   from  #tmpBranch tb with (nolock)
   join Miracle.dbo.MatrixInBranch mb with (nolock) on mb.branchId = tb.branchId and mb.[disable] = '0'
   join Miracle.dbo.MatrixTitle mt with (nolock) on mb.matrixTitleId = mt.matrixTitleId
   where mt.[disable] = '0' and mt.dateBegin <= @parentCustomerDate
    and isnull(mt.dateEnd, dateadd(year, 100, @parentCustomerDate)) >= @parentCustomerDate
    and mt.parentCustomerId = @customerId and mt.isOrders = '1'

   --todo не вижу зачем. Если что раскомментировать
   /*
   -- Получение категорий для матриц
   update #tmpMatrixToBranch
   set categoryName = mc.categoryName,
    categoryId = mc.matrixCategoryId
   from #tmpMatrixToBranch mt with (nolock)
   left join Miracle.dbo.MatrixCategory mc with (nolock)
   on mt.matrixTitleId = mc.matrixTitleId and mc.categoryType = '1' and mc.[disable] = '0'
   join Miracle.dbo.MatrixCategoryBranch mcb with (nolock)
   on mcb.matrixCategoryId = mc.matrixCategoryId and mcb.branchId = mt.branchId and isnull(mcb.branchChecked, '0') = '1'
   */

   -- получаем все topRegId из матриц
   insert into #tmpTopRegId (
    matrixDataId, matrixTitleId, fabrType, topRegId, branchId, minOst, porogZakaz, [priority], createDate, outOfAutoOrder
   )
   select md.matrixDataId,
    mtb.matrixTitleId,
    md.fabrType,
    md.topRegId,
    mtb.branchId,
    isnull(nullif(isnull(mdc.minOst, md.minOst), 0), 1),
    isnull(mdc.porogZakaz, md.porogZakaz),
    mtb.[priority],
    mtb.createDate,
    mtb.outOfAutoOrder
   from #tmpMatrixToBranch mtb with (nolock)
   join Miracle.dbo.MatrixData md with (nolock) on mtb.matrixTitleId = md.matrixTitleId and md.[disable] = '0'
   left join Miracle.dbo.MatrixDataCategory mdc with (nolock)
   on mdc.matrixDataId = md.MatrixDataId and mdc.matrixCategoryId = isnull(mtb.categoryId, '0')

   /******** "Разворачивание" позиций с учетом производтелей BEGIN ***********/
   -- Без учета производителя
   insert into #tmpMatrixData (
    matrixTitleId, drugId, formId, fabrId, branchId, minOst, porogZakaz, [priority], createDate, outOfAutoOrder
   )
   select distinct tri.matrixTitleId,
    r1.DRUGID,
    r1.FORMID,
    r1.FABRID,
    tri.branchId,
    tri.minOst,
    tri.porogZakaz,
    tri.[priority],
    tri.createDate,
    tri.outOfAutoOrder
   from #tmpTopRegId tri with (nolock)
   left join Megapress.dbo.REGISTRY r1 with (nolock) on r1.regId = tri.topRegId --and r1.FLAG = '0'
    --left join Megapress.dbo.REGISTRY r2 with (nolock)
    --on r2.DRUGID = r1.DRUGID and r2.FORMID = r1.FORMID and r2.FLAG = '0'
   where tri.fabrType = '0'

   -- С учетом приоритета производителя. Отбираем только те позиции, у которых приоритет производителя больше нуля.
   insert into #tmpMatrixData (
    matrixTitleId, drugId, formId, fabrId, branchId, minOst, porogZakaz, [priority], createDate, outOfAutoOrder
   )
   select distinct tri.matrixTitleId,
    r2.DRUGID,
    r2.FORMID,
    r2.FABRID,
    tri.branchId,
    tri.minOst,
    tri.porogZakaz,
    tri.[priority],
    tri.createDate,
    tri.outOfAutoOrder
   from #tmpTopRegId tri with (nolock)
   left join Miracle.dbo.MatrixFabrPriority mf with (nolock, forceseek) on mf.matrixDataId = tri.matrixDataId
   left join Megapress.dbo.REGISTRY r1 with (nolock) on r1.regId = tri.topRegId and r1.FLAG = '0'
   left join Megapress.dbo.REGISTRY r2 with (nolock)
   on r2.DRUGID = r1.DRUGID and r2.FORMID = r1.FORMID and r2.FABRID = mf.fabrId and r2.FLAG = '0'
   where tri.fabrType = '1' and mf.fabrPriority > 0

   -- С учетом конкретного производителя.
   insert into #tmpMatrixData (
    matrixTitleId, drugId, formId, fabrId, branchId, minOst, porogZakaz, [priority], createDate, outOfAutoOrder
   )
   select distinct tri.matrixTitleId,
    r1.DRUGID,
    r1.FORMID,
    r1.FABRID,
    tri.branchId,
    tri.minOst,
    tri.porogZakaz,
    tri.[priority],
    tri.createDate,
    tri.outOfAutoOrder
   from #tmpTopRegId tri with (nolock)
   left join Megapress.dbo.REGISTRY r1 with (nolock) on r1.regId = tri.topRegId and r1.FLAG = '0'
   where tri.fabrType = '2'
   /******** "Разворачивание" позиций с учетом производтелей END ***********/

   -- получаем все уникальные drugId, formId и fabrId с наименьшим приоритетом
   insert into #tmpUnicDrugIdFormId (
    [priority], createDate, drugId, formId, fabrId, outOfAutoOrder
   )
   select min(tmd.[priority]), max(tmd.createDate), tmd.drugId, tmd.formId, tmd.fabrId, tmd.outOfAutoOrder
   from #tmpMatrixData tmd with (nolock)
   group by tmd.drugId, tmd.formId, tmd.fabrId, tmd.outOfAutoOrder

   -- обновление уникальных drugId, formId и fabrId
   update ur
   set ur.minOst = md.minOst,
    ur.porogZakaz = md.porogZakaz,
    ur.matrixTitleId = md.matrixTitleId,
    ur.branchId = md.branchId
   from #tmpUnicDrugIdFormId ur with (nolock)
   join #tmpMatrixData md with (nolock) on md.createDate = ur.createDate and isnull(md.[priority], 0) = isnull(ur.[priority],0)
    and ur.drugId = md.drugId and ur.formId = md.formId and ur.fabrId = md.fabrId

   -- получаем поставщиков для матриц
   insert into #tmpMatrixDistr (
    matrixTitleId, branchId, distrId
   )
   select mb.matrixTitleId, mb.branchId, md.distrId
   from #tmpMatrixToBranch mb with (nolock)
   left join Miracle.dbo.MatrixDistrib md with (nolock) on mb.matrixTitleId = md.matrixTitleId and md.checkDistrib = '1'

   -- добавление недостающих матричных товаров
   insert into #tmpZakaz(
    autoZakazDataId, branchId, drugId, formId, zakaz, zakazOrig, ost, tovInAWay, threshold1, threshold2, speedMax, kEff
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
    zd.kEff--oa.autoZakazTitleId, a.drugId, a.formId
    -- todo не попадает товар, которого нету в autozakazdata, если так быть не должно смотреть сюда
   from #tmpUnicDrugIdFormId a
   left join Miracle.dbo.AutoZakazData zd with (nolock) on zd.drugId = a.drugId
    and zd.formId = a.formid and zd.autoZakazTitleId in (select value from @docList)
   left join Miracle.dbo.AutoZakazTitle zt with (nolock)
   on zt.autoZakazTitleId = zd.autoZakazTitleId
   where isnull(nullif(zd.zakazToOrder, 0), zd.zakazMatrix) > 0 and not exists(
    select 1
    from #tmpZakaz tz with (nolock)
    where a.drugId = tz.drugId and a.formId = tz.formId and a.branchId = tz.branchId
    )
   option (optimize for unknown)
   /*
   from (
    select drugiD, formid, branchId from #tmpUnicDrugIdFormId u where not exists (
     select 1 from #tmpZakaz tz with (nolock) where u.drugId = tz.drugId and u.formId = tz.formId and u.branchId = tz.branchId
     )
    group by u.drugId, u.formId, u.branchId
   ) a
   outer apply (
    select distinct ad.autoZakazTitleId
    from #tmpZakaz tz with (nolock)
    left join Miracle.dbo.AutoZakazData ad with (nolock) on tz.autoZakazDataId = ad.autoZakazDataId
    where tz.branchId = a.branchId
   ) oa
   left join Miracle.dbo.AutoZakazData zd with (nolock) on zd.autoZakazTitleId = oa.autoZakazTitleId and zd.drugId = a.drugId
	and zd.formId = a.formid
   left join Miracle.dbo.AutoZakazTitle zt with (nolock) on zt.autoZakazTitleId = zd.autoZakazTitleId and zt.branchId = a.branchId
   */

   declare @matrixRegIdList dbo.IntList

   insert into @matrixRegIdList(value)
   select distinct vr.REGID
   from #tmpZakaz tz with (nolock)
   left join Megapress.dbo.Registry vr with (nolock) on vr.DRUGID = tz.drugId and vr.FORMID = tz.formId
   where tz.parentDrugId is null and parentFormId is null and not exists (select 1 from @regIdList rl where rl.value = vr.REGID)

   -- Получаем нужные товары для размещения
   insert into #tmpPriceList(
    regId, drugId, formId, fabrId, distrId, sql2DistrId, priceId, price, qntOst, minZakaz, srokG, ratio, distr, priceFabr
   )
    exec Miracle.dbo.AutoZakazGetSvodPriceByRegId_v3 @customerId, @historId, @matrixRegIdList

   -- todo ???
   update tpl
   set [block] = '0'
   from #tmpPriceList tpl
   where tpl.[block] is null

   -- обновление сводного прайс листа для Матричных товаров. Мин остаток, порог заказа.
   update tp
   set tp.matrixTitleId = ur.matrixTitleId,
    tp.minOst = ur.minOst,
    tp.porogZakaz = ur.porogZakaz
   from #tmpPriceList tp with (nolock)
   join #tmpUnicDrugIdFormId ur with (nolock)
   on ur.formId = tp.formId and ur.drugId = tp.drugId and ur.fabrId = tp.fabrId
  end

 /*
 -- родительский дубль для новых добавленных товаров
 ;with cte as (
 select isnull(oa1.drugId, isnull(oa.drugId, a.drugId)) as parentdrugId,
  isnull(oa1.formId, isnull(oa.formId, a.formId)) as parentformId,
  a.drugId, a.formId
 from (
  select distinct tz.drugId, tz.formId
  from #tmpZakaz tz with (nolock)
  where tz.parentDrugId is null and parentFormId is null
 ) a
 outer apply (
  select dr.drugid, dr.formid
  from Miracle.dbo.DoubleRegistry dr with (nolock)
  where dr.drugId = a.drugId and dr.formId = a.formId and dr.parentCustomerId = @customerId and dr.parentDoubleRegistryId = 0
 ) oa
 outer apply (
  select dr1.drugId, dr1.formId
  from Miracle.dbo.DoubleRegistry dr1 with (nolock)
  outer apply (
   select dr.parentDoubleRegistryId
   from Miracle.dbo.DoubleRegistry dr with (nolock)
   where dr.drugId = a.drugId and dr.formId = a.formId and dr.parentCustomerId = @customerId and dr.parentDoubleRegistryId != 0
  ) oa2
  where oa2.parentDoubleRegistryId = dr1.doubleRegistryId
 ) oa1
)

  update tz
  set parentDrugId = c.parentdrugId, parentFormId = c.parentformId
  from #tmpZakaz tz
  left join cte c on c.drugId = tz.drugId and c.formId = tz.formId
  where tz.parentDrugId is null and tz.parentFormId is null and tz.drugId = c.drugId and tz.formId = tz.formId
  */

 update tz
 set parentDrugId = c.parentdrugId, parentFormId = c.parentformId
 from #tmpZakaz tz
 outer apply (
  select tz2.drugId, tz2.formId, isnull(tdp.parentDrugId, tz.drugid) as parentDrugId, isnull(tdp.parentFormId, tz.formId) as parentFormId
  from #tmpZakaz tz2 with (nolock)
  left join #tmpDoublesForPriority tdp with (nolock) on tz2.drugId = tdp.drugId and tz2.formId = tdp.formId
  where tz2.drugid = tz.drugId and tz2.formId = tz.formId
 ) c
 where tz.parentDrugId is null and tz.parentFormId is null and tz.drugId = c.drugId and tz.formId = tz.formId

 -- недостающие родительские дубли от матричные товаров
 insert into #tmpZakazParent (
  parentDrugId, parentFormId, zakaz, zakazOrig, speedMax, threshold1, threshold2, ost, tovInAWay, branchId
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
 where not exists (
  select 1
  from #tmpZakazParent tzp with (nolock)
  where tz.parentDrugId = tzp.parentDrugId and tz.parentFormId = tzp.parentFormId and tz.branchId = tzp.branchId
  )

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

 -- todo думаю, нужны корректировки по профилю автозаказа
-- Получение срока годности
 if @srokG = '1'
  begin
   declare
    @defaultProfile int
   -- Дефолтный профиль настроек

   -- Получение дефолтного профиля
   select @defaultProfile = autoZakazProfileId
   from Miracle.dbo.AutoZakazProfile azp with (nolock)
   where azp.customerid = @customerId and azp.isDefault = 1
   option (optimize for unknown)

   -- получаем настройку по остаточным срокам годности
   insert into #tmpSrokG(
    branchId, srokGInMonth
   )
   select tb.branchId, isnull(azp.srokGInMonth, @defSrokGInMonth)
   from #tmpBranch tb with (nolock)
   left join Miracle.dbo.AutoZakazProfileToBranch azptb with (nolock)
   on azptb.branchId = tb.branchId and azptb.[Disable] = 0
   left join Miracle.dbo.AutoZakazProfile azp with (nolock)
   on azp.autoZakazProfileId = isnull(azptb.autoZakazProfileId, @defaultProfile)

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
  end

-- Создём индексы
 create index Ind1 on #tmpPriceList (drugId, formId)
  include (minZakaz, srokG, ratio, [block], distrId, distr)

 create index Ind2 on #tmpPriceList (regId)
  include (minZakaz, srokG, ratio, [block], distrId, distr)

 create index Ind1 on #tmpDistrPriority (distrId, branchId)
  include ([priority])

-- признаки для размещения
 declare
  @moveDone int = 0,
  @orderDone int = 0,
  @insertedRows int

 if @marketing = '1'
  begin

   -- необходимая категория асна
   declare @typeId int = 9
   -- созвездие (обязательная матрица)
   declare @constellationType varchar(20) = 'MANDATORY_MATRIX'
   -- код региона
   declare @regionCode int

   select @regionCode = substring(INN, 1, 2)
   from Miracle.dbo.Customer c with(nolock)
   where c.CustomerID = @customerId
   option(optimize for unknown)

   insert into #tmpConstellationProductList (branchId, drugId, formId, minOst)
   select co.branchId, vr.drugId, vr.formId, max(cp.quantity)
   from Miracle.dbo.ConstellationOptions co with (nolock)
   join #tmpBranch bmd with (nolock) on bmd.branchId = co.branchId
   join Miracle.dbo.ConstellationBranch cb with (nolock) on cb.map_pharmacy_id = co.branchId and cb.Disable = '0'
   join Miracle.dbo.ConstellationMarketingAction ca with (nolock) on ca.marketing_action_id = cb.marketing_action_id and ca.[Disable] = '0'
    and ca.[state] = 0 and ca.marketing_action_type = @constellationType and @curDate between ca.date_start and ca.date_end
   join Miracle.dbo.ConstellationProducts cp with (nolock) on cp.marketing_action_id = ca.marketing_action_id and cp.[Disable] = '0'
   join Miracle.dbo.ConstellationNomenclature cn with (nolock) on cn.product_id = cp.product_id and cn.[Disable] = '0' and cn.map_nomenclature_code != 0
   join Megapress.dbo.Registry vr with (nolock) on vr.regId = cn.map_nomenclature_code
   where isnull(co.HighlightNeedMatrixSvodPrice, '0') = '1'
   group by co.branchId, vr.drugid, vr.formid

   --собираем неликвидные товары из созвездия с выполненым планом
   insert into #tmpConstellationCompleteList (branchId, drugId, formId, parentDrugId, parentFormId, qnt)
   select tz.branchId, tz.drugId, tz.formId, tz.parentDrugId, tz.parentFormId, tz.zakaz
   from #tmpZakaz tz with (nolock)
   where isnull(tz.noMoveDay, 0) >= (
    select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = tz.branchId
   ) and tz.ost >= isnull((
                           select isnull(tcpl.minOst, 0)
                           from #tmpConstellationProductList tcpl with (nolock)
                           where tcpl.branchId = tz.branchId and tcpl.formId = tz.formId and tcpl.drugId = tz.drugId
                          ), 0)

   update tz
   set zakaz = 0
   from #tmpZakaz tz with (nolock)
   join #tmpConstellationCompleteList tcc with (nolock) on tcc.branchId = tz.branchId and tcc.drugId = tz.drugId and tcc.formId = tz.formId

   update tzp
   set zakaz = zakaz - tcc.qnt
   from #tmpZakazParent tzp with (nolock)
   join #tmpConstellationCompleteList tcc with (nolock) on tcc.branchId = tzp.branchId and tcc.parentDrugId = tzp.parentDrugId
    and tcc.parentFormId = tzp.parentFormId

   --таблица привязок
   create table #tmpASNABinding (
    branchId int,
    nnt int,
    regId int
   )

-- товары к заказу
   create table #tmpASNAOrder (
    branchId int,
    regId int
   )

   update tb
   set tb.rrId = b.rrId,
    tb.storeId = b.clientId
   from #tmpBranch tb with (nolock)
   left join Miracle.dbo.ASNABranch b with (nolock) on b.branchId = tb.branchId

   insert into #tmpASNABinding(
    branchId, nnt, regId
   )
   select distinct tb.branchId, b.nnt, b.regId
   from #tmpBranch tb with (nolock)
   join Miracle.dbo.BindingsASNARegId b with (nolock) on tb.rrId = b.rrId

   create index Ind1 on #tmpASNABinding (regId)

   insert into #tmpASNAOrder(
    branchId, regId
   )
   select tb.branchId, ao.regId
   from #tmpBranch tb with (nolock)
   join Miracle.dbo.ASNAMarketingOrder ao with (nolock) on ao.branchId = tb.branchId and ao.[disable] = '0'

   -- todo 12%
   insert into #tmpASNAMarketing(
    branchId, regid, drugId, formId, nnt, minQnt
   )
   select distinct tb.branchId, r.regid, r.DRUGID, r.FORMID, ap.nnt, iif(isnull(ap.qnt, 0) > 0, 1, 0)
   from #tmpBranch tb with (nolock)
   join Miracle.dbo.ASNAAction a with (nolock) on a.storeId = tb.storeId
   left join Miracle.dbo.ASNAActionPlans ap with (nolock) on ap.actionId = a.Id and ap.storeId = tb.storeId
   left join #tmpASNABinding t with (nolock) on t.nnt = ap.nnt
   left join Megapress.dbo.REGISTRY r with (nolock) on r.REGID = t.regId
   where a.typeCode = @typeId
    and a.[status] = '0'
    and ap.[status] = '0'
    and t.regId is not null
    and @curDate between a.beginDate and a.endDate
    and MONTH(ap.periodYM) = MONTH(@curDate)
	and iif(isnull(ap.qnt, 0) > 0, 1, 0) != 0
   option (optimize for unknown)

   insert into #tmpMarketingIgnorePercent (branchId, [percent])
   select b.branchId, iif(cp.value = '', 0, cast(replace(cp.value, ',', '.') as numeric(15, 5)))
   from Miracle.dbo.CustomerParams cp with (nolock)
   join #tmpBranch b with (nolock) on b.branchId = cp.CustomerFillID
   where cp.Name = 'mPercIgnorSupplier'

   insert into #tmpMarketingDistrPriority (branchId, regId, distrId, [percent], [priority], drugid, formid)
   select tmi.BranchID, tpl.regId, c.CustomerID, tmi.[percent], 0, r.drugid, r.formid
   from #tmpMarketingIgnorePercent tmi with (nolock)
   join #tmpASNAMarketing tpl with (nolock) on tpl.branchId = tmi.branchId
   join Miracle.dbo.ASNARecommendedSuppliers asr with (nolock) on asr.disable = '0' and asr.nnt = tpl.nnt and asr.endDate > GETDATE()
    and SUBSTRING(asr.inn, 1, 2) = @regionCode
   join Miracle.dbo.Customer c with (nolock) on c.inn = asr.inn
   join #tmpDistrPriority tdp with (nolock) on tdp.distrId = c.CustomerID
   left join Miracle.dbo.ASNAIgnoreRecommendedSuppliers air with (nolock) on air.BranchID in (select tb.branchId from #tmpBranch tb)
    and air.nnt = asr.nnt and air.isIgnore = '0'
   left join Megapress.dbo.REGISTRY r with (nolock) on r.REGID = tpl.regID
   where isnull(air.isIgnore, '0') = '0'
   group by tmi.branchId, tpl.regID, c.CustomerID, tmi.[percent], r.drugid, r.formid

   drop table #tmpASNABinding
   drop table #tmpASNAOrder
  end

 if @donor = '1'
  begin

   declare @count int = 0 -- заглушка, на случай зацикливания

   -- перемещение от доноров
   while @moveDone = 0
    begin
     -- делаем размещение
     ;
     with t as (
      select tp.donorDataId,
       row_number() over (partition by tz.parentDrugId,tz.parentFormId order by
        tp.maxZakaz desc, -- максимальное кол-во, которое донор может отдать
        tp.srokG, -- срок годности
        tp.qntOst desc, -- остаток
        tp.donorDataId -- идентификатор строки, на случай если все характеристики равны
        ) [pNumber]
      from #tmpZakaz tz with (nolock)
      join #tmpPriceList tp with (nolock, index = Ind1)
      on tz.drugId = tp.drugId and tz.formId = tp.formId and tp.donorDataId is not null
      where tz.complete = 0
     ),
      r as (
       select drugId, formId, donorBranchId, sum(zakaz) sumZak
       from #tmpOrder with (nolock)
       group by drugId, formId, donorBranchId
      ),
      o as (
       select z.autoZakazDataId,
        tbl.priceFabr,
        tbl.regId,
        z.branchId,
        z.drugId,
        z.formId,
        z.parentDrugId,
        z.parentFormId,
        tbl.donorBranchId,
        tbl.naklDataId,
        z.noMoveDay,
        -- суммарное кол-во заказа не больше того, что может отдать донор
        iif(tbl.zakaz < tbl.maxZakaz - isnull(r.sumZak, 0), tbl.zakaz, tbl.maxZakaz - isnull(r.sumZak, 0)) zakaz,
        row_number() over (partition by z.parentDrugId,z.parentFormId order by tbl.pNumber,
         iif(tbl.zakaz < tbl.maxZakaz - isnull(r.sumZak, 0), tbl.zakaz, tbl.maxZakaz - isnull(r.sumZak, 0)) desc,
         tbl.qntOst desc, tbl.srokG desc) rowNum
       from #tmpZakaz z with (nolock)
       left join #tmpZakazParent tzp with (nolock)
       on tzp.parentDrugId = z.parentDrugId and tzp.parentFormId = z.parentFormId and z.branchId = tzp.branchId
       outer apply(
        select top 1 tp.regId,
         tp.distrId,
         tp.donorBranchId,
         tp.naklDataId,
         t.pNumber,
         iif(tzp.zakaz < tp.qntOst, tzp.zakaz, tp.qntOst) zakaz,
         maxZakaz,
         tp.priceFabr,
         tp.qntOst,
         tp.srokG
        from #tmpPriceList tp with (nolock, index = Ind1)
        join t on t.donorDataId = tp.donorDataId
        join #tmpMove tm with (nolock) on z.branchId = tm.recepientBranchId and tp.donorBranchId = tm.donorBranchId
        left join r with (nolock) on r.drugId = tp.drugId and r.formId = tp.formId and r.donorBranchId = tp.donorBranchId
        left join #tmpDonorSrokG s with (nolock) on s.branchId = tp.donorBranchId
        where tp.qntOst > 0 and tp.drugId = z.drugId and tp.formId = z.formId and isnull(r.sumZak, 0) < tp.maxZakaz --and tp.maxZakaz > tzp.zakaz
         -- срок годности
         and datediff(day, @curDate, tp.srokG) >= s.srokGInDayForMove
        order by t.pNumber, tp.qntOst desc, tp.srokG desc
       ) tbl
       left join r with (nolock) on r.formId = z.formId and r.drugId = z.drugId and r.donorBranchId = tbl.donorBranchId
       where z.complete = 0 and (z.zakazOrig > 0 or tzp.zakazOrig > 0) and tbl.donorBranchId is not null and not exists (
        select 1
        from #tmpUnicDrugIdFormId tud with (nolock)
        where tud.outOfAutoOrder = 1 and tud.formid = z.formid and tud.drugid = z.drugid
        )
      )

     insert
     into #tmpOrder (
      autoZakazDataId,
      regId,
      branchId,
      drugId,
      formId,
      parentDrugId,
      parentFormId,
      donorBranchId,
      naklDataId,
      zakaz,
      isNew,
      priceFabr
     )
     select o.autoZakazDataId,
      o.regId,
      o.branchId,
      o.drugId,
      o.formId,
      o.parentDrugId,
      o.parentFormId,
      o.donorBranchId,
      o.naklDataId,
      o.zakaz,
      '1',
      o.priceFabr
     from o with (nolock)
     where o.rowNum = 1 and isnull(o.zakaz, 0) > 0 and isnull(o.noMoveDay, 0) < (
      select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = o.branchId
     )

     set @insertedRows = @@ROWCOUNT

     --select @insertedRows as [Перемещение]

     if @insertedRows > 0
      begin
       -- удаляем уже размещенные позиции прайс-листа
       delete
       from #tmpPriceList
       where naklDataId in (
        select o.naklDataId
        from #tmpOrder o with (nolock)
        where o.naklDataId is not null and o.isNew = '1'
       )

       -- уменьшаем потребности
       ;
       with t as (
        select o.branchId, o.parentDrugId, o.parentFormId, sum(o.zakaz) sumZak
        from #tmpOrder o with (nolock)
        where o.isNew = '1'
        group by o.parentDrugId, o.parentFormId, o.branchId
       )
       update tzp
       set tzp.zakaz = tzp.zakaz - t.sumZak
       from #tmpZakazParent tzp with (nolock)
       join t on t.parentDrugId = tzp.parentDrugId and tzp.parentFormId = t.parentFormId and t.branchId = tzp.branchId

       -- удаляем удовлетворенные потребности
       ;
       with t as (
        select tz.autoZakazDataId
        from #tmpZakaz tz with (nolock)
        left join #tmpZakazParent tzp with (nolock)
        on tz.parentDrugId = tzp.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
        where tzp.zakaz <= 0 and isnull(tz.zakazOrig, 0) > 0
       )
       update #tmpZakaz
       set zakaz = 0,
        complete = 1
       where autoZakazDataId in (
        select autoZakazDataId
        from t with (nolock)
       )

       update #tmpZakazParent
       set zakaz = 0,
        complete = 1
       where zakaz <= 0 and isnull(zakazOrig, 0) > 0

       update #tmpOrder
       set isNew = '0'

      end
     --      else
--       begin
--        set @moveDone = 1
--       end

     --set @moveDone = 1
     --set @orderDone = 1

     set @count = @count + 1

     if not exists (
      select 1
      from #tmpZakazParent tzp with (nolock)
      outer apply (
       select sum(tpl.qntOst) as ost, sum(tpl.maxZakaz) as maxZakaz
       from #tmpPriceList tpl with (nolock)
       join #tmpZakaz tz with (nolock) on tz.drugId = tpl.drugId and tz.formId = tpl.formId
       join #tmpMove tm with (nolock) on tm.recepientBranchId = tz.branchId and tpl.donorBranchId = tm.donorBranchId and tm.autoZakazTitleId is not null
       where tz.parentDrugId = tzp.parentDrugId and tz.parentFormId = tzp.parentFormId and tpl.donorDataId is not null
        and tzp.branchId = tz.branchId
       group by tpl.drugId, tpl.formId
      ) oa
      where oa.maxZakaz > 0 and oa.ost > 0 and tzp.zakaz > 0
       and tzp.branchId in (
       select tm.recepientBranchId
       from #tmpMove tm with (nolock)
       where tm.recepientBranchId = tzp.branchId and tm.autoZakazTitleId is not null
      ) and not exists (
       select 1
       from #tmpZakaz z with (nolock)
       join #tmpUnicDrugIdFormId tud with (nolock) on tud.formid = z.formid and tud.drugid = z.drugid
       where tud.outOfAutoOrder = 1 and z.parentDrugId = tzp.parentDrugId and z.parentFormId = tzp.parentFormId
       ) and not exists (
       select 1
       from #tmpZakaz z with (nolock)
       where z.parentDrugId = tzp.parentDrugId and z.parentFormId = tzp.parentFormId
        and isnull(z.noMoveDay, 0) > (select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = tzp.branchId)
       ) and exists (
       select 1
       from #tmpPriceList tpl1 with (nolock)
       join #tmpZakaz tz1 with (nolock) on tz1.drugId = tpl1.drugId and tz1.formId = tpl1.formId
       where tpl1.maxZakaz > (
        select isnull(sum(t.zakaz), 0) as zakaz
        from #tmpOrder t with (nolock)
        where t.drugId = tpl1.drugId and t.formId = tpl1.formId and t.branchId = tzp.branchId and t.donorBranchId = tpl1.donorBranchId
       ) and tz1.parentDrugId = tzp.parentDrugId and tz1.parentFormId = tzp.parentFormId and tz1.branchId = tzp.branchId
       )
      ) or @count = 5
      begin
       set @moveDone = 1
      end

     if not exists(
      select 1 from #tmpZakaz
      )
      begin
       set @orderDone = 1
      end

    end
  end

-- размещаем в сводном прайс-листе
 while @orderDone = 0
  begin

   -- Если нужно искать товар по drugId и formId
   if @parentDF_or_regId like '%1%'
    begin

     -- todo 15% поправить все инсерты сюда
     insert into #tmpPriceListIdList (
      priceId, branchId, pNumber
     )
     select tp.priceId,
      tz.branchId,
      row_number() over (
       partition by
       tz.parentDrugId,
       tz.parentFormId,
       tz.branchId
       order by
        iif(tzp.zakaz >= tp.minZakaz and tz.zakaz % tp.ratio = 0, 0, 1), -- подходящие значения кратности и мин заказа
       /*iif(mp2.[priority] is null, 2, 1) * (isnull(min_price, tp.price) + (tp.price/10000))*/
        tp.price * isnull(dp.[priority], 1) * isnull(fp.[priority], 1), -- цена
        tp.srokG desc, -- срок годности
        tp.qntOst desc, -- остаток
        tp.priceId -- идентификатор строки прайс-листа, на случай если все характеристики равны
       ) [pNumber]
     from #tmpZakaz tz with (nolock)
     join #tmpZakazParent tzp with (nolock)
     on tzp.branchId = tz.branchId and tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId
     join #tmpPriceList tp with (nolock, index = Ind1) on tp.drugId = tz.drugId and tp.formId = tz.formId
     left join #tmpDistrPriority dp with (nolock, index = Ind1) on dp.distrId = tp.distrId and dp.branchId = tz.branchId
     left join #tmpFabrPriority fp with (nolock) on tp.regId = fp.regId
--      outer apply (
--       select min(isnull(tp1.price,0)) as min_price
--       from #tmpPriceList tp1 with (nolock)
--       left join #tmpDistrPriority dp1 with (nolock, index = Ind1) on dp1.distrId = tp1.distrId and dp1.branchId = tz.branchId
--       left join #tmpFabrPriority fp1 with (nolock) on tp1.regId = fp1.regId
--       left join #tmpDoublesForPriority tdp with (nolock) on tdp.drugId = tp1.drugId and tdp.formId = tp1.formId
--       where tp1.distrId is not null and tp1.[block] = '0' and isnull(tdp.parentDrugId,tp1.drugId) = tz.parentDrugId
--        and isnull(tdp.parentFormId, tp1.formid) = tz.parentFormId
--      ) mp
--      outer apply (
--       select top 1 tmd.[priority] -- тут пусто
--       from #tmpMarketingDistrPriority tmd with (nolock)
--       where tmd.drugid = tz.drugid and tmd.distrId = tp.distrId and tmd.formid = tz.formid
--        and (mp.min_price + (mp.min_price / 100.0 * tmd.[percent])) < tp.price
--      ) mp2
     where tp.distrId is not null and tp.[block] = '0' and tz.complete = 0
     option (optimize for unknown)

     -- cte - все предложения по позициям по которым есть потребность упорядоченные по цене
     ;
     with r as (
      select drugId, formId, sum(zakaz) sumZak, branchId
      from #tmpOrder with (nolock)
      group by drugId, formId, branchId
     ),
      o as (
       select z.autoZakazDataId,
        tbl.regId,
        z.branchId,
        z.drugId,
        z.formId,
        z.parentDrugId,
        z.parentFormId,
        z.ost,
        tbl.minOst,
        tbl.distrId,
        tbl.price,
        tbl.priceFabr,
        tbl.priceId,
        tbl.porogZakaz,
        row_number() over (partition by
         z.parentDrugId,
         z.parentFormId,
         z.branchId
         order by tbl.pNumber) rowNum,
        productCountToOrder as zakaz,
        z.noMoveDay,
        tbl.matrixTitleId,
        tbl.qntOst
       from #tmpZakaz z with (nolock)
       left join #tmpZakazParent tzp with (nolock)
       on tzp.parentDrugId = z.parentDrugId and tzp.parentFormId = z.parentFormId and tzp.branchId = z.branchId and tzp.complete = 0
       left join r with (nolock) on r.drugId = z.drugId and r.formId = z.formId and r.branchId = z.branchId
       left join #tmpSrokG s with (nolock) on s.branchId = z.branchId
       outer apply(
        select top 1 *,
		 iif(zakaz0 <= qntOst, zakaz0, case when qntOst % ratio = 0 then qntOst 
										    when qntOst % ratio > 0 and qntOst - qntOst % ratio >= minZakaz then qntOst - qntOst % ratio
									  end
		 ) as productCountToOrder
        from (
         select top 100
          case
           -- Если товар матричный
           when f.zakazMatrix > f.zakaz then
            case when f.zakazMatrix < f.porogZakaz then f.porogZakaz else f.zakazMatrix end
           -- Если товар не матричный
           when f.zakazMatrix <= f.zakaz then
            case
             -- Если заказ больше чем требуемый минимум
             when tzp.zakaz >= f.minZakaz then
              case
               when tzp.zakaz % f.ratio = 0 then tzp.zakaz -- если заказ кратный
               when f.zakaz1 <= tzp.threshold2 - isnull(r.sumZak, 0)
                then f.zakaz1 -- если заказ не кратный и можно увеличить
               when f.zakaz2 >= tzp.threshold2 - isnull(r.sumZak, 0)
                then f.zakaz2 -- если заказ не кратный и надо уменьшить
               end
             -- Если заказ меньше чем требуемый минимум
             else
              case
               when f.minZakaz % f.ratio = 0 and f.minZakaz <= tzp.threshold2 - isnull(r.sumZak, 0)
                then f.minZakaz -- если мин заказ кратный и можно увеличить
               when f.zakaz3 <= tzp.threshold2 - isnull(r.sumZak, 0)
                then f.zakaz3 -- если мин заказ не кратный и можно увеличить
               end
             end
           else 0
           end zakaz0,
          f.*
         from (
          select top 100 tp.regId,
           tp.price [price],
           tp.distrId,
           pil.priceId,
           pil.pNumber,
           tzp.zakaz,
           tp.ratio,
           tp.minZakaz,
           tp.priceFabr,
           tp1.matrixTitleId,
           tp1.minOst,
           tp1.porogZakaz,
           tp.qntOst,
           -- заказ увеличенный по кратности
           ((tzp.zakaz + tp.ratio) - (tzp.zakaz % tp.ratio)) zakaz1,
           -- заказ уменьшенный по кратности
           (tzp.zakaz - (tzp.zakaz % tp.ratio)) zakaz2,
           -- заказ увеличенный до требуемого минимума и увеличенный по кратности
           iif(tp.minZakaz = tp.ratio, tp.minZakaz, ((tp.minZakaz + tp.ratio) - (tp.minZakaz % tp.ratio))) zakaz3,
           -- заказ для матричного товара
           iif(tp1.matrixTitleId > 0, iif(tzp.zakaz > tp1.minOst, tzp.zakaz, 
				iif(tp1.minOst - tzp.ost - tzp.tovInAWay > 0, tp1.minOst - tzp.ost - tzp.tovInAWay, 0)), 0) zakazMatrix
          from #tmpPriceList tp with (nolock, index = Ind1)
          join #tmpPriceListIdList pil with (nolock) on pil.priceId = tp.priceId and pil.branchId = z.branchId
          join #tmpDistrPriority dp with (nolock, index = Ind1) on z.branchId = dp.branchId and tp.distrId = dp.distrId
          left join #tmpMatrixDistr md with (nolock) on z.branchId = md.branchId and tp.matrixTitleId = md.matrixTitleId
          left join #tmpPriceList tp1 with (nolock) on tp1.drugId = z.parentDrugId and tp1.formId = z.parentFormId
          where tp.drugId = z.drugId and tp.formId = z.formId and (
           (
            -- Если товар не матричный
            (tp.matrixTitleId is null or tp1.minOst < 1)
             -- минимальный заказ
             and (
             (tzp.zakaz >= tp.minZakaz) or -- если заказ больше чем минимальное количество
              (iif(tp.minZakaz = tp.ratio, tp.minZakaz, (tp.minZakaz + tp.ratio) - (tp.minZakaz % tp.ratio))
               <= tzp.threshold2 - isnull(r.sumZak, 0)) -- увеличение заказа до требуемого минимума
             )
             -- срок годности
             and (datediff(month, @curDate, tp.srokG) >= s.srokGInMonth or @srokG = '0')
             -- кратность
             and (
             (tzp.zakaz % tp.ratio = 0) or -- если заказ кратный
              (((tzp.zakaz + tp.ratio) - (tzp.zakaz % tp.ratio)) <= tzp.threshold2 - isnull(r.sumZak, 0))
              or -- увеличение заказа до нужной кратности
              ((tzp.zakaz > tp.ratio) and ((tzp.zakaz - (tzp.zakaz % tp.ratio))
               >= tzp.threshold2 - isnull(r.sumZak, 0))) -- уменьшение заказа до нужной кратности
             )
            )
            or
            (
             -- Если товар матричный
             tp1.matrixTitleId > 0
              -- учёт поставщиков для матричных товаров
              and tp1.distrId = iif(md.distrId is null, tp1.distrId, md.distrId)
              -- минимальный заказ
              and (
              -- Соответствие минимальному заказу поставщика
              (isnull(tp1.minOst, 0) - isnull(tzp.ost, 0) - isnull(tzp.tovInAWay, 0) >= tp1.minZakaz) or
               -- Минимальный заказ не превышающий 20-ти дневный прогноз
               ((tp1.minZakaz + tp1.ratio) - (tp1.minZakaz % tp1.ratio) <= tzp.threshold1 - isnull(r.sumZak, 0) or tzp.threshold1 = 0)
              )
              -- срок годности
              and (datediff(month, @curDate, tp.srokG) >= s.srokGInMonth or @srokG = '0')
              and exists (select 1 from #tmpMatrixData tmd1 with (nolock) where tmd1.drugId = z.drugId and tmd1.formId = z.formId
                                                                           and tmd1.branchId = z.branchId)
              -- кратность
              and (tp1.minOst - tzp.ost - tzp.tovInAWay) % tp1.ratio = 0
             )
           )
          order by pil.pNumber
         ) f
        ) f2
        where 
		 -- убираем предложения поставщиков с остатком меньше кол-ва к заказу, если есть предложения с остатком больше либо равно товара к заказу
		 (f2.zakaz0 <= f2.qntOst and exists (select 1 from #tmpPriceList pls where f2.regId = pls.regId and pls.qntOst >= f2.zakaz0)) or
		 -- либо убираем с остатком больше, если других нету, с учетом минимального остатка и кратности
		 (f2.zakaz0 > f2.qntOst and not exists (select 1 from #tmpPriceList pls where f2.regId = pls.regId and pls.qntOst >= f2.zakaz0)
		   and f2.qntOst >= f2.minZakaz and 
		   (f2.qntOst % f2.ratio = 0 or (f2.qntOst % f2.ratio > 0 and f2.qntOst - f2.qntOst % f2.ratio >= f2.minZakaz))
		 )
       ) tbl
       where z.complete = 0 and (z.zakazOrig > 0 or tzp.zakazOrig > 0) and tbl.priceId is not null and not exists (
        select 1
        from #tmpUnicDrugIdFormId tud with (nolock)
        where tud.outOfAutoOrder = 1 and tud.drugid = z.drugid and tud.formid = z.formid
        )
      )
     insert
     into #tmpOrder (
      autoZakazDataId,
      regId,
      branchId,
      drugId,
      formId,
      parentDrugId,
      parentFormId,
      zakaz,
      price,
      priceId,
      distrId,
      isNew,
      priceFabr
     )
     select o.autoZakazDataId,
      o.regId,
      o.branchId,
      o.drugId,
      o.formId,
      o.parentDrugId,
      o.parentFormId,
      o.zakaz,
      o.price,
      o.priceId,
      o.distrId,
      '1',
      o.priceFabr
     from o with (nolock)
     where o.rowNum = 1 and isnull(o.zakaz, 0) > 0 and isnull(o.zakaz, 0) >= isnull(o.porogZakaz, 0) and (
      (o.matrixTitleId is not null and o.ost < o.minOst) or isnull(o.noMoveDay, 0) < (
       select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = o.branchId
      ) or (isnull(o.noMoveDay, 0) >= (
       select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = o.branchId
      ) and not exists (
       select 1
       from #tmpConstellationCompleteList  tcc with (nolock)
       where tcc.branchId = o.branchId and tcc.drugId = o.drugId and tcc.formId = o.formId
       ))
      )
    end
    -- Иначе по regId
   else
    if @parentDF_or_regId like '%2%'
     begin
      insert into #tmpPriceListIdList (
       priceId, pNumber
      )
      select tp.priceId,
       row_number() over (
        partition by
        tz.regId
        order by
         iif(tz.zakaz >= tp.minZakaz and tz.zakaz % tp.ratio = 0, 0, 1), -- подходящие значения кратности и мин заказа
         iif(mp2.[priority] is null, 2, 1) * (isnull(min_price, tp.price) + (tp.price/10000)) * isnull(dp.[priority], 1) * isnull(fp.[priority], 1), -- цена
         tp.srokG desc, -- срок годности
         tp.qntOst desc, -- остаток
         tp.priceId -- идентификатор строки прайс-листа, на случай если все характеристики равны
        ) [pNumber]
      from #tmpZakaz tz with (nolock)
      join #tmpPriceList tp with (nolock, index = Ind2) on tz.regId = tp.regId
      left join #tmpDistrPriority dp with (nolock, index = Ind1)
      on dp.distrId = tp.distrId and dp.branchId = tz.branchId
      left join #tmpFabrPriority fp with (nolock) on tp.regId = fp.regId
      outer apply (
       select min(isnull(tp1.price,0)) as min_price
       from #tmpPriceList tp1 with (nolock)
       left join Megapress.dbo.Registry vr with (nolock) on vr.REGID = tp1.regId
       left join #tmpDistrPriority dp1 with (nolock, index = Ind1) on dp1.distrId = tp1.distrId and dp1.branchId = tz.branchId
       left join #tmpFabrPriority fp1 with (nolock) on tp1.regId = fp1.regId
       left join #tmpDoublesForPriority tdp with (nolock) on tdp.drugId = vr.drugId and tdp.formId = vr.formId
       where tp1.distrId is not null and tp1.[block] = '0' and isnull(tdp.parentDrugId,vr.drugId) = tz.parentDrugId
        and isnull(tdp.parentFormId, vr.formid) = tz.parentFormId
        and (@reorder = '0' or (@reorder = '1' and isnull(tz.distrId, 0) != tp1.distrId
        or (tz.distrId = tp1.distrId and tz.oldPrice != tp1.price)))
       /*
           select min(isnull(tp1.price,0)) as min_price
           from #tmpPriceList tp1 with (nolock)
           left join Megapress.dbo.Registry vr with (nolock) on vr.REGID = tp1.regId
           left join #tmpDistrPriority dp1 with (nolock, index = Ind1) on dp1.distrId = tp1.distrId and dp1.branchId = tz.branchId
           left join #tmpFabrPriority fp1 with (nolock) on tp1.regId = fp1.regId
           outer apply (
            select dr1.drugId, dr1.formId
            from Miracle.dbo.DoubleRegistry dr1 with (nolock)
            outer apply (
             select dr.parentDoubleRegistryId
             from Miracle.dbo.DoubleRegistry dr with (nolock)
             where dr.drugId = vr.DRUGID and dr.formId = vr.FORMID and dr.parentDoubleRegistryId != 0 and dr.parentCustomerId = @customerId
            ) oa1
            where dr1.doubleRegistryId = oa1.parentDoubleRegistryId
           ) oa
           where tp1.distrId is not null and tp1.[block] = '0' and isnull(oa.drugid,vr.drugId) = tz.parentDrugId
            and isnull(oa.formid, vr.formid) = tz.parentFormId
            and (@reorder = '0' or (@reorder = '1' and isnull(tz.distrId, 0) != tp1.distrId
            or (tz.distrId = tp1.distrId and tz.oldPrice != tp1.price)))
            */
      ) mp
      outer apply (
       select top 1 tmd.[priority] -- тут пусто
       from #tmpMarketingDistrPriority tmd with (nolock)
       where tmd.regId = tz.regId and tmd.distrId = tp.distrId
        and (mp.min_price + (mp.min_price / 100.0 * tmd.[percent])) < tp.price
      ) mp2
      where tp.distrId is not null and tp.[block] = '0' and tz.complete = 0
       -- Скрытие поставщика если у него не изменилась цена при переотказе
       and (@reorder = '0' or (@reorder = '1' and isnull(tz.distrId, 0) != tp.distrId
       or (tz.distrId = tp.distrId and tz.oldPrice != tp.price)))
      option (optimize for unknown)

      -- cte - все предложения по позициям по которым есть потребность упорядоченные по цене
      ;
      with r as (
       select regId, sum(zakaz) sumZak, branchId
       from #tmpOrder with (nolock)
       group by regId, branchId
      ),
       o as (
        select z.autoZakazDataId,
         tbl.regId,
         z.branchId,
         z.drugId,
         z.formId,
         z.parentDrugId,
         z.parentFormId,
         z.ost,
         tbl.minOst,
         tbl.distrId,
         tbl.price,
         tbl.priceFabr,
         tbl.priceId,
         tbl.porogZakaz,
         row_number() over (partition by
          (CASE WHEN @type_update = '1' then z.distrId end),
          z.regId
          order by tbl.pNumber) rowNum,
         productCountToOrder as zakaz,
         z.noMoveDay,
         tbl.matrixTitleId,
         tbl.qntOst
        from #tmpZakaz z with (nolock)
        left join #tmpZakazParent tzp with (nolock) on tzp.parentRegId = z.regId and tzp.branchId = z.branchId and tzp.complete = 0
        left join r with (nolock) on r.regId = z.regId and r.branchId = z.branchId
        left join #tmpSrokG s with (nolock) on s.branchId = z.branchId
        outer apply(
         select top 1 *,
		 iif(zakaz0 <= qntOst, zakaz0, case when qntOst % ratio = 0 then qntOst 
										    when qntOst % ratio > 0 and qntOst - qntOst % ratio >= minZakaz then qntOst - qntOst % ratio
									  end
		 ) as productCountToOrder
         from (
          select top 100
           case
            -- Если товар матричный
            when f.zakazMatrix > f.zakaz then
             case when f.zakazMatrix < f.porogZakaz then f.porogZakaz else f.zakazMatrix end
            -- Если товар не матричный
            when f.zakazMatrix <= f.zakaz then
             case
              -- Если заказ больше чем требуемый минимум
              when tzp.zakaz >= f.minZakaz then
               case
                when tzp.zakaz % f.ratio = 0 then tzp.zakaz -- если заказ кратный
                when f.zakaz1 <= tzp.threshold2 - isnull(r.sumZak, 0)
                 then f.zakaz1 -- если заказ не кратный и можно увеличить
                when f.zakaz2 >= tzp.threshold2 - isnull(r.sumZak, 0)
                 then f.zakaz2 -- если заказ не кратный и надо уменьшить
                end
              -- Если заказ меньше чем требуемый минимум
              else
               case
                when f.minZakaz % f.ratio = 0 and f.minZakaz <= tzp.threshold2 - isnull(r.sumZak, 0)
                 then f.minZakaz -- если мин заказ кратный и можно увеличить
                when f.zakaz3 <= tzp.threshold2 - isnull(r.sumZak, 0)
                 then f.zakaz3 -- если мин заказ не кратный и можно увеличить
                end
              end
            else 0
            end zakaz0,
           f.*
          from (
           select top 100 tp.regId,
            tp.price [price],
            tp.distrId,
            pil.priceId,
            pil.pNumber,
            tzp.zakaz,
            tp.ratio,
            tp.minZakaz,
            tp.priceFabr,
            tp1.matrixTitleId,
            tp1.minOst,
            tp1.porogZakaz,
            tp.qntOst,
            -- заказ увеличенный по кратности
            ((tzp.zakaz + tp.ratio) - (tzp.zakaz % tp.ratio)) zakaz1,
            -- заказ уменьшенный по кратности
            (tzp.zakaz - (tzp.zakaz % tp.ratio)) zakaz2,
            -- заказ увеличенный до требуемого минимума и увеличенный по кратности
            iif(tp.minZakaz = tp.ratio, tp.minZakaz, ((tp.minZakaz + tp.ratio) - (tp.minZakaz % tp.ratio))) zakaz3,
            -- заказ для матричного товара
            iif(tp1.matrixTitleId > 0, iif(tzp.zakaz > tp1.minOst, tzp.zakaz, 
				iif(tp1.minOst - tzp.ost - tzp.tovInAWay > 0, tp1.minOst - tzp.ost - tzp.tovInAWay, 0)), 0) zakazMatrix
           from #tmpPriceList tp with (nolock, index = Ind1)
           join #tmpPriceListIdList pil with (nolock) on pil.priceId = tp.priceId
           join #tmpDistrPriority dp with (nolock, index = Ind1) on z.branchId = dp.branchId and tp.distrId = dp.distrId
           left join #tmpMatrixDistr md with (nolock) on z.branchId = md.branchId and tp.matrixTitleId = md.matrixTitleId
           left join #tmpPriceList tp1 with (nolock) on tp1.regId = tzp.parentRegId
           where (@type_update != '1' or (@type_update = '1' and tp.distrId = isnull(z.distrId, tp.distrId)))
            and tp.regId = z.regId and (
            (
             -- Если товар не матричный
             (tp.matrixTitleId is null or tp1.minOst < 1)
              -- минимальный заказ
              and (
              (tzp.zakaz >= tp.minZakaz) or -- если заказ больше чем минимальное количество
               (iif(tp.minZakaz = tp.ratio, tp.minZakaz, (tp.minZakaz + tp.ratio) - (tp.minZakaz % tp.ratio))
                <= tzp.threshold2 - isnull(r.sumZak, 0)) -- увеличение заказа до требуемого минимума
              )
              -- срок годности
              and (datediff(month, @curDate, tp.srokG) >= s.srokGInMonth or @srokG = '0')
              -- кратность
              and (
              (tzp.zakaz % tp.ratio = 0) or -- если заказ кратный
               (((tzp.zakaz + tp.ratio) - (tzp.zakaz % tp.ratio)) <= tzp.threshold2 - isnull(r.sumZak, 0))
               or -- увеличение заказа до нужной кратности
               ((tzp.zakaz > tp.ratio) and ((tzp.zakaz - (tzp.zakaz % tp.ratio))
                >= tzp.threshold2 - isnull(r.sumZak, 0))) -- уменьшение заказа до нужной кратности
              )
             )
             or
             (
              -- Если товар матричный
              tp1.matrixTitleId > 0
               -- учёт поставщиков для матричных товаров
               and tp1.distrId = iif(md.distrId is null, tp1.distrId, md.distrId)
               -- минимальный заказ
               and (
               (tp1.minOst - tzp.ost - tzp.tovInAWay >= tp1.minZakaz) or -- если заказ больше чем минимальное количество
                ((tp1.minZakaz + tp1.ratio) - (tp1.minZakaz % tp1.ratio)
                 <= tzp.threshold1 - isnull(r.sumZak, 0) or tzp.threshold1 = 0) -- увеличение заказа до требуемого минимума
               )
               -- срок годности
               and (datediff(month, @curDate, tp.srokG) >= s.srokGInMonth or @srokG = '0')
               and exists (select 1 from #tmpMatrixData tmd1 with (nolock) where tmd1.drugId = z.drugId and tmd1.formId = z.formId
                                                                            and tmd1.branchId = z.branchId)
               -- кратность
               and (tp1.minOst - tzp.ost - tzp.tovInAWay) % tp1.ratio = 0
              )
            )
           order by pil.pNumber
          ) f
         ) f2
         where 
		 -- убираем предложения поставщиков с остатком меньше кол-ва к заказу, если есть предложения с остатком больше либо равно товара к заказу
		 (f2.zakaz0 <= f2.qntOst and exists (select 1 from #tmpPriceList pls where f2.regId = pls.regId and pls.qntOst >= f2.zakaz0)) or
		 -- либо убираем с остатком больше, если других нету, с учетом минимального остатка и кратности
		 (f2.zakaz0 > f2.qntOst and not exists (select 1 from #tmpPriceList pls where f2.regId = pls.regId and pls.qntOst >= f2.zakaz0)
		   and f2.qntOst >= f2.minZakaz and 
		   (f2.qntOst % f2.ratio = 0 or (f2.qntOst % f2.ratio > 0 and f2.qntOst - f2.qntOst % f2.ratio >= f2.minZakaz))
		 )
        ) tbl
        where z.complete = 0 and (z.zakazOrig > 0 or tzp.zakazOrig > 0) and tbl.priceId is not null and not exists (
         select 1
         from #tmpUnicDrugIdFormId tud with (nolock)
         join Megapress.dbo.REGISTRY r with (nolock) on r.drugid = tud.drugid and r.formid = tud.formid
         where tud.outOfAutoOrder = 1 and r.regid = z.regid
         )
       )
      insert
      into #tmpOrder (
       autoZakazDataId,
       regId,
       branchId,
       drugId,
       formId,
       parentDrugId,
       parentFormId,
       zakaz,
       price,
       priceId,
       distrId,
       isNew,
       priceFabr
      )
      select o.autoZakazDataId,
       o.regId,
       o.branchId,
       o.drugId,
       o.formId,
       o.parentDrugId,
       o.parentFormId,
       o.zakaz,
       o.price,
       o.priceId,
       o.distrId,
       '1',
       o.priceFabr
      from o with (nolock)
      where o.rowNum = 1 and isnull(o.zakaz, 0) > 0 and isnull(o.zakaz, 0) >= isnull(o.porogZakaz, 0) and (
       (o.matrixTitleId is not null and o.ost < o.minOst) or isnull(o.noMoveDay, 0) < (
        select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = o.branchId
       )
       )
     end

   set @insertedRows = @@ROWCOUNT

   --select @insertedRows as [Заказ у поставщика]

   if @insertedRows > 0
    begin
     -- удаляем уже размещенные позиции прайс-листа
     update #tmpPriceList
     set ordered = 1
     where priceId in (
      select o.priceId
      from #tmpOrder o with (nolock)
      where o.priceId is not null and o.isNew = '1'
     )

     if @parentDF_or_regId like '%1%'
      begin
       -- уменьшаем потребности
       ;
       with t as (
        select o.branchId, o.parentDrugId, o.parentFormId, sum(o.zakaz) sumZak
        from #tmpOrder o with (nolock)
        where o.isNew = '1'
        group by o.parentDrugId, o.parentFormId, o.branchId
       )
       update tzp
       set tzp.zakaz = tzp.zakaz - t.sumZak
       from #tmpZakazParent tzp with (nolock)
       join t on t.parentDrugId = tzp.parentDrugId and tzp.parentFormId = t.parentFormId and tzp.branchId = t.branchId

       -- удаляем удовлетворенные потребности
       ;
       with t as (
        select tz.autoZakazDataId
        from #tmpZakaz tz with (nolock)
        left join #tmpZakazParent tzp with (nolock)
        on tz.parentDrugId = tzp.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
        where tzp.zakaz <= 0 and isnull(tz.zakazOrig, 0) > 0
       )
       update #tmpZakaz
       set zakaz = 0,
        complete = 1
       where autoZakazDataId in (
        select autoZakazDataId
        from t with (nolock)
       )
      end

     if @parentDF_or_regId like '%2%'
      begin
       -- уменьшаем потребности
       ;
       with t as (
        select o.branchId, o.regId, sum(o.zakaz) sumZak
        from #tmpOrder o
        where o.isNew = '1'
        group by o.regId, o.branchId
       )
       update tzp
       set tzp.zakaz = tzp.zakaz - t.sumZak
       from #tmpZakazParent tzp with (nolock)
       join t on t.regId = tzp.parentRegId and t.branchId = tzp.branchId

       -- удаляем удовлетворенные потребности
       ;
       with t as (
        select tz.autoZakazDataId
        from #tmpZakaz tz with (nolock)
        left join #tmpZakazParent tzp with (nolock)
        on tz.regId = tzp.parentRegId and tz.branchId = tzp.branchId
        where tzp.zakaz <= 0 and isnull(tz.zakazOrig, 0) > 0
       )
       update #tmpZakaz
       set zakaz = 0,
        complete = 1
       where autoZakazDataId in (
        select autoZakazDataId
        from t with (nolock)
       )
      end

     update #tmpZakazParent
     set zakaz = 0,
      complete = 1
     where zakaz <= 0 and isnull(zakazOrig, 0) > 0

     update #tmpOrder
     set isNew = '0'

    end

   set @orderDone = 1

  end

-- уменьшение ненужных перемещений
 create table #tmpOrderExceed (
  autoZakazDataId int,
  exceed int
 )

 ;with cte as (
  select tz.autoZakazDataId, sum(isnull(t.zakaz, 0)) zakazFact, tz.zakazOrig
  from #tmpZakaz tz with (nolock)
  left join #tmpOrder t with(nolock) on tz.autoZakazDataId = t.autoZakazDataId
  where tz.zakazOrig > 0
  group by tz.autoZakazDataId, tz.zakazOrig
 )
  insert into #tmpOrderExceed(autoZakazDataId, exceed)
  select autoZakazDataId, zakazFact - zakazOrig
  from cte where zakazFact > zakazOrig

 if exists (select 1 from #tmpOrderExceed)
  begin

   ;with cte as (
    select oe.autoZakazDataId,
     t.naklDataId,
     oe.exceed,
     row_number() over (partition by oe.autoZakazDataId order by t.zakaz desc) number
    from #tmpOrderExceed oe with (nolock)
    left join #tmpOrder t on oe.autoZakazDataId = t.autoZakazDataId and t.naklDataId is not null
   )
    update o
    set o.zakaz = iif(o.zakaz <= cte.exceed, 0, o.zakaz - cte.exceed)
    from #tmpOrder o with(nolock)
    join cte on cte.autoZakazDataId = o.autoZakazDataId and cte.naklDataId = o.naklDataId and cte.number = 1

   delete from #tmpOrder
   where autoZakazDataId in (select autoZakazDataId from #tmpOrderExceed with(nolock)) and zakaz = 0

  end

 drop table #tmpOrderExceed

-- ограничение
 if exists(select 1 from #tmpAutoZakazProfile where useRestriction = 1)
  begin

   -- исключенные из заказа позиции
   create table #tmpExcludedOrderList (
    autoZakazDataId int,     -- идетнтификатор строки документа автозаказа
    regId int,               -- идентификатор товара
    branchId int,            --идентификатор филиала
    drugId int,              -- идентификатор наименования
    formId int,              -- идентификатор формы выпуска
    parentDrugId int,        -- родительский идентификатор наименования
    parentFormId int,        -- родительский идентификатор формы выпуска
    distrId int,             -- идентификатор поставщика (megapress)
    donorBranchId int,       -- идентификатор филиала донора
    naklDataId int,          -- идентификатор строки накладной
    priceId bigint,          -- идентифкатор строки прайс-листа,
    price numeric(15, 2),    -- цена
    zakaz int,               -- количество заказа (может изменять в зависимости от кратности)
    pNumber smallint,        -- номер цены в сводном прайс-листе
    isNew char(1),           -- признак новой записи
    priceFabr numeric(15, 2) -- цена производителя
   )

   insert into #tmpPlanOrder(
    branchid, planOrder
   )
   select ppo.BranchId, ppo.PlanOrder
   from #tmpBranch b with (nolock)
   left join Miracle.dbo.KWPlanProceedsAndOrder ppo with (nolock)
   on ppo.BranchId = b.branchId and ppo.PlanDate = cast(@curDate as date)
   left join #tmpOrder o with (nolock) on b.branchId = o.branchId
   group by ppo.BranchId, ppo.PlanOrder

   declare
    @branchesCount int,
    @currentRow int = 0,
    @currentBranchId int,
	@excludedCount int = 0

   select @branchesCount = count(distinct tb.branchId) from #tmpBranch tb with (nolock)

   while @currentRow < @branchesCount
    begin

     select @currentBranchId = tb.branchId
     from #tmpBranch tb with (nolock)
     order by tb.branchId asc
     offset @currentRow row fetch first 1 rows only

     if exists(select 1 from #tmpAutoZakazProfile where branchId = @currentBranchId and useRestriction = 1)
      and exists(select 1 from #tmpPlanOrder where branchid = @currentBranchId and planOrder > 0)
      begin

       while((select sum(o.price * o.zakaz)
              from #tmpOrder o with (nolock)
              where o.branchId = @currentBranchId and o.donorBranchId is null
              group by o.branchId) >
        (select tpo.planOrder from #tmpPlanOrder tpo with (nolock) where tpo.branchid = @currentBranchId) and exists
        (select 1
         from #tmpPlanOrder tpo with (nolock)
         where tpo.branchid = @currentBranchId and tpo.planOrder is not null)
        )
        begin

		 set @excludedCount = (select count(*) from #tmpExcludedOrderList)

         delete top (1) t
         output deleted.autoZakazDataId,
          deleted. regId,
          deleted.branchId,
          deleted.drugId,
          deleted.formId,
          deleted.parentDrugId,
          deleted.parentFormId,
          deleted.distrId,
          deleted.donorBranchId,
          deleted.naklDataId,
          deleted.priceId,
          deleted.price,
          deleted.zakaz,
          deleted.pNumber,
          deleted.isNew,
          deleted.priceFabr
          into #tmpExcludedOrderList (autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId,
                                      distrId, donorBranchId, naklDataId, priceId, price, zakaz, pNumber, isNew,
                                      priceFabr)
         from #tmpOrder t
         outer apply (
			select top 1 tmo.branchId, tmo.drugId, tmo.formId
            from #tmpZakaz tz
            left join #tmpOrder tmo with (nolock) on tmo.autoZakazDataId = tz.autoZakazDataId
            where tz.branchId = @currentBranchId and tmo.branchId is not null and tmo.drugId is not null and tmo.formId is not null and
				  tz.complete = 1 and tmo.zakaz > 0 and tmo.donorBranchId is null
				  -- БДН созвездия
				  and not exists (
				 	select 1
					from #tmpConstellationProductList tpl with (nolock)
					where tpl.drugId = tmo.drugId and tpl.formId = tmo.formId and tpl.branchId = tmo.branchId
				  )
				  -- матричные товары
				  and not exists (
					select 1
					from #tmpUnicDrugIdFormId tud with (nolock)
					where tud.formid = tmo.formid and tud.drugid = tmo.drugid and tud.branchId = tmo.branchId
				  )
				  -- БДН АСНА
				  and not exists (
					select 1
					from #tmpASNAMarketing tmp with (nolock)
					where tmp.formid = tmo.formid and tmp.drugid = tmo.drugid and tmp.branchId = tmo.branchId
				  )
            group by tmo.branchId, tmo.drugId, tmo.formId, tz.kEff
            order by tz.kEff asc, tmo.drugId desc, tmo.formId desc
		 ) oa
         where t.branchId = oa.branchId and t.formId = oa.formId and t.drugId = oa.drugId and t.donorBranchId is null

		 -- выходим, если удалять больше нечего
		 if @excludedCount = (select count(*) from #tmpExcludedOrderList)
		  break
        end

       while exists(select 1
                    from #tmpExcludedOrderList
                    where zakaz * price <= (select max(tpo.planOrder) - sum(o.price * o.zakaz)
                                            from #tmpOrder o with (nolock)
                                            left join #tmpPlanOrder tpo with (nolock) on tpo.branchid = o.branchId
                                            where o.branchId = @currentBranchId and o.donorBranchId is null
                                            group by o.branchId)
        )
        begin
         insert into #tmpOrder (
          autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId,
          distrId, donorBranchId, naklDataId, priceId, price, zakaz, pNumber, isNew, priceFabr
         )
         select top 1 teol.autoZakazDataId,
          teol.regId,
          teol.branchId,
          teol.drugId,
          teol.formId,
          teol.parentDrugId,
          teol.parentFormId,
          teol.distrId,
          teol.donorBranchId,
          teol.naklDataId,
          teol.priceId,
          teol.price,
          teol.zakaz,
          teol.pNumber,
          teol.isNew,
          teol.priceFabr
         from #tmpExcludedOrderList teol with (nolock)
         left join #tmpZakaz tz with (nolock) on tz.autoZakazDataId = teol.autoZakazDataId
         where teol.zakaz * teol.price <= (select max(tpo.planOrder) - sum(o.price * o.zakaz)
                                           from #tmpOrder o with (nolock)
                                           left join #tmpPlanOrder tpo with (nolock) on tpo.branchid = o.branchId
                                           where o.branchId = @currentBranchId and o.donorBranchId is null
                                           group by o.branchId)
         order by tz.kEff desc, tz.drugId asc, tz.formId asc

         delete teol
         from #tmpExcludedOrderList teol
         where exists(select 1 from #tmpOrder t where t.autoZakazDataId = teol.autoZakazDataId and t.donorBranchId is null)
        end

       while exists(select 1
                    from #tmpExcludedOrderList
                    where price <= (select max(tpo.planOrder) - sum(o.price * o.zakaz)
                                    from #tmpOrder o with (nolock)
                                    left join #tmpPlanOrder tpo with (nolock) on tpo.branchid = o.branchId
                                    where o.branchId = @currentBranchId and o.donorBranchId is null
                                    group by o.branchId)
        )
        begin

         declare @currentAutoZakazDataId int, @currentZakazCount int

         select @currentAutoZakazDataId = teol.autoZakazDataId, @currentZakazCount = teol.zakaz
         from #tmpExcludedOrderList teol with (nolock)
         left join #tmpZakaz tz with (nolock) on tz.autoZakazDataId = teol.autoZakazDataId
         where price <= (select max(tpo.planOrder) - sum(o.price * o.zakaz)
                         from #tmpOrder o with (nolock)
                         left join #tmpPlanOrder tpo with (nolock) on tpo.branchid = o.branchId
                         where o.branchId = @currentBranchId and o.donorBranchId is null
                         group by o.branchId)
         order by tz.kEff desc, tz.drugId asc, tz.formId asc

         while((select teol.price
                from #tmpExcludedOrderList teol with (nolock)
                where teol.autoZakazDataId = @currentAutoZakazDataId) *
          @currentZakazCount > (select max(tpo.planOrder) - sum(o.price * o.zakaz)
                                from #tmpOrder o with (nolock)
                                left join #tmpPlanOrder tpo with (nolock) on tpo.branchid = o.branchId
                                where o.branchId = @currentBranchId and o.donorBranchId is null
                                group by o.branchId) and @currentZakazCount > 1)
          begin
           set @currentZakazCount = @currentZakazCount - 1
          end

         insert into #tmpOrder (
          autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId,
          distrId, donorBranchId, naklDataId, priceId, price, zakaz, pNumber, isNew, priceFabr
         )
         select top 1 teol.autoZakazDataId,
          teol.regId,
          teol.branchId,
          teol.drugId,
          teol.formId,
          teol.parentDrugId,
          teol.parentFormId,
          teol.distrId,
          teol.donorBranchId,
          teol.naklDataId,
          teol.priceId,
          teol.price,
          @currentZakazCount,
          teol.pNumber,
          teol.isNew,
          teol.priceFabr
         from #tmpExcludedOrderList teol with (nolock)
         where @currentZakazCount * teol.price <= (select max(tpo.planOrder) - sum(o.price * o.zakaz)
                                                   from #tmpOrder o with (nolock)
                                                   left join #tmpPlanOrder tpo with (nolock) on tpo.branchid = o.branchId
                                                   where o.branchId = @currentBranchId and o.donorBranchId is null
                                                   group by o.branchId)
          and teol.autoZakazDataId = @currentAutoZakazDataId

         delete teol
         from #tmpExcludedOrderList teol
         where exists(select 1 from #tmpOrder t where t.autoZakazDataId = teol.autoZakazDataId and t.donorBranchId is null)
        end

       update tz
       set tz.excluded = 1
       from #tmpZakaz tz with (nolock)
       left join #tmpExcludedOrderList te with (nolock) on te.autoZakazDataId = tz.autoZakazDataId
       where te.autoZakazDataId = tz.autoZakazDataId and not exists(select 1
                                                                    from #tmpOrder tmp with (nolock)
                                                                    where tmp.autoZakazDataId = te.autoZakazDataId)

       update tb
       set tb.restrictionSum = tp.planOrder
       from #tmpBranch tb
       left join #tmpPlanOrder tp on tp.branchid = tb.branchId
       where tb.branchId = @currentBranchId

       -- добавляем в заказ с нулевым заказом, чтобы потом заного не анализировать
       insert into #tmpOrder (
        autoZakazDataId, regId, branchId, drugId, formId, parentDrugId, parentFormId,
        distrId, donorBranchId, naklDataId, priceId, price, zakaz, pNumber, isNew, priceFabr
       )
       select teol.autoZakazDataId,
        teol.regId,
        teol.branchId,
        teol.drugId,
        teol.formId,
        teol.parentDrugId,
        teol.parentFormId,
        teol.distrId,
        teol.donorBranchId,
        teol.naklDataId,
        teol.priceId,
        teol.price,
        0,
        teol.pNumber,
        teol.isNew,
        teol.priceFabr
       from #tmpExcludedOrderList teol with (nolock)
       left join #tmpZakaz tz with (nolock) on tz.autoZakazDataId = teol.autoZakazDataId
       where not exists(select 1 from #tmpOrder t where t.autoZakazDataId = teol.autoZakazDataId)

      end
     else
      if exists(select 1 from #tmpAutoZakazProfile where branchId = @currentBranchId and useRestriction = 1)
       begin

        update #tmpBranch
        set comment = iif(isnull(comment, '') = '', '', comment + ', ')
         + 'ограничение не выполнено: отсутствует план заказа на дату'
        where branchId = @currentBranchId

       end

     set @currentRow = @currentRow + 1
    end
   drop table #tmpExcludedOrderList
  end

-- проставляем комментарии
 if @parentDF_or_regId like '%1%'
  begin

   -- Срок годности
   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '1'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
    and isnull(tzp.zakazOrig, 0) != 0
   join #tmpPriceList tp with (nolock) on tp.drugId = tz.drugId and tp.formId = tz.formId
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp.distrId and tz.branchId = tdp.branchId)
   left join #tmpSrokG s with (nolock) on s.branchId = tz.branchId
   left join #tmpPriceList tp1 with (nolock) on tp1.drugId = tz.drugId and tp1.formId = tz.formId
    and datediff(month, @curDate, tp1.srokG) > s.srokGInMonth
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp1.distrId and tz.branchId = tdp.branchId)
   where tz.complete = 0 and tp1.price is null

   -- Минимальный заказ
   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '2'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
    and isnull(tzp.zakazOrig, 0) != 0
   join #tmpPriceList tp with (nolock) on tp.drugId = tz.drugId and tp.formId = tz.formId
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp.distrId and tz.branchId = tdp.branchId)
   left join #tmpPriceList tp2 with (nolock)
   on tp2.drugId = tz.drugId and tp2.formId = tz.formId and tzp.zakazOrig >= tp2.minZakaz
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp2.distrId and tz.branchId = tdp.branchId)
   where tz.complete = 0 and tp2.price is null

   -- Кратность
   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '3'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
    and isnull(tzp.zakazOrig, 0) != 0
   join #tmpPriceList tp with (nolock) on tp.drugId = tz.drugId and tp.formId = tz.formId
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp.distrId and tz.branchId = tdp.branchId)
   left join #tmpPriceList tp3 with (nolock)
   on tp3.drugId = tz.drugId and tp3.formId = tz.formId and tzp.zakazOrig % tp3.ratio = 0
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp3.distrId and tz.branchId = tdp.branchId)
   where tz.complete = 0 and tp3.price is null

   -- Блокировка
   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '4'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
    and isnull(tzp.zakazOrig, 0) != 0
   join #tmpPriceList tp with (nolock) on tp.drugId = tz.drugId and tp.formId = tz.formId
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp.distrId and tz.branchId = tdp.branchId)
   left join #tmpPriceList tp4 with (nolock) on tp4.drugId = tz.drugId and tp4.formId = tz.formId and tp4.[block] != '1'
    and exists(select 1
               from #tmpDistrPriority tdp with (nolock)
               where tdp.distrId = tp4.distrId and tz.branchId = tdp.branchId)
   where tz.complete = 0 and tp4.price is null

   -- Ограничение суммы заказа
   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '5'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
    and isnull(tzp.zakazOrig, 0) != 0
   where tz.excluded = 1

   -- Отсутствует предложение
   update tz
   set tz.commentIds = '0'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
    and isnull(tzp.zakazOrig, 0) != 0
   where not exists (
    select 1
    from #tmpPriceList tpl with (nolock) where tpl.drugId = tz.drugId and tpl.formId = tz.formId
                                          and tpl.distrId in (select distrId from #tmpDistrPriority with (nolock) where branchId = tz.branchId)
    )

   -- Неликвидный товар
   update tz
   set tz.commentIds = iif(isnull(tz.commentIds, '') = '', '', tz.commentIds + ',') + '6'
   from #tmpZakaz tz with (nolock)
   join #tmpZakazParent tzp with (nolock)
   on tzp.parentDrugId = tz.parentDrugId and tzp.parentFormId = tz.parentFormId and tz.branchId = tzp.branchId
    and isnull(tzp.zakazOrig, 0) != 0
   left join #tmpOrder o with (nolock) on tz.branchId = o.branchId and tz.drugId = o.drugId and o.formId = tz.formId
   where
   -- обычный товар, без матрицы, маркетингов: асны, созвездия
   (isnull(tz.noMoveDay, 0) >= (
    select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = tz.branchId
   ) and not exists ( -- не в матрице
    select 1
    from #tmpUnicDrugIdFormId tu with (nolock)
    where tu.drugId = tz.drugid and tu.formId = tz.formid and tu.branchId = tz.branchid
   ) and not exists ( -- не в созвездии
	select 1
	from #tmpConstellationProductList tpl with (nolock)
	where tpl.drugId = tz.drugId and tpl.formId = tz.formId and tpl.branchId = tz.branchId
   ) and not exists ( -- не в АСНА
    select 1
	from #tmpASNAMarketing tam with (nolock)
	where tam.drugId = tz.drugId and tam.formId = tz.formId and tam.branchId = tz.branchId
   )) or
   -- неликвидный товар из созвездия, с выполненым планом
   (exists (-- в созвездии
    select 1 from #tmpConstellationProductList tcpl with (nolock) where tcpl.branchId = tz.branchId and tcpl.drugId = tz.drugId
                                                                   and tcpl.formId = tz.formId
    ) and exists (-- неликвидные товары созвездия с выполненым планом
    select 1 from #tmpConstellationCompleteList tcpl with (nolock) where tcpl.branchId = tz.branchId and tcpl.drugId = tz.drugId
                                                                    and tcpl.formId = tz.formId
    )) or
	-- неликвидный товар из АСНА с выполненым планом
	(
	 -- превышение дней без продаж
	 isnull(tz.noMoveDay, 0) >= (
     select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = tz.branchId
     )
	 and exists ( -- в АСНА
	  select 1
	  from #tmpASNAMarketing tam with (nolock)
	  where tam.drugId = tz.drugId and tam.formId = tz.formId and tam.branchId = tz.branchId
	 )
	 and exists ( -- план выполнен
	  select 1
	  from #tmpASNAMarketing tam with (nolock)
	  where tam.drugId = tz.drugId and tam.formId = tz.formId and tam.branchId = tz.branchId and tz.ost >= tam.minQnt
	 )
	) or
	-- неликвидный товар из матрицы с выполненым планом
	(
	 -- превышение дней без продаж
	 isnull(tz.noMoveDay, 0) >= (
     select noMoveDaysMax from #tmpAutoZakazProfile tap with (nolock) where tap.branchId = tz.branchId
     )
	 and exists ( -- в матрице
      select 1
      from #tmpUnicDrugIdFormId tu with (nolock)
      where tu.drugId = tz.drugid and tu.formId = tz.formid and tu.branchId = tz.branchid
     )
	 and exists ( -- план выполнен
      select 1
      from #tmpUnicDrugIdFormId tu with (nolock)
      where tu.drugId = tz.drugid and tu.formId = tz.formid and tu.branchId = tz.branchid and tz.ost >= tu.minOst
     )
	)

   -- Матрица исключения
   update tz
   set commentIds = '7'
   from #tmpZakaz tz
   where exists(
    select 1
    from #tmpUnicDrugIdFormId tud with (nolock)
    where tud.outOfAutoOrder = 1 and tz.drugid = tud.drugid and tz.formid = tud.formid
    )

   update tz
   set commentIds = '8'
   from #tmpZakaz tz
   where commentIds is null and tz.complete = 0 and exists (
    select 1
    from #tmpPriceList tpl with (nolock) where tpl.drugId = tz.drugId and tpl.formId = tz.formId
                                          and tpl.distrId in (select distrId from #tmpDistrPriority with (nolock) where branchId = tz.branchId) and tpl.qntOst < tz.zakazOrig
    )

   update tz
   set tz.commentIds = '[' + tz.commentIds + ']'
   from #tmpZakaz tz
   where tz.commentIds is not null

  end

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


 drop table #tmpDouble
 drop table #tmpMatrixData
 drop table #tmpMatrixDistr
 drop table #tmpMatrixToBranch
 drop table #tmpMove
 drop table #tmpTopRegId
 drop table #tmpUnicDrugIdFormId
 drop table #tmpZakazParent
 drop table #tmpPriceList
 drop table #tmpPriceListIdList
 drop table #tmpPlanOrder
 drop table #tmpFabrPriority
 drop table #tmpDistr
 drop table #tmpMarketingDistrPriority
 drop table #tmpMarketingIgnorePercent
 drop table #tmpDoublesForPriority
 drop table #tmpAutoZakazProfile
 drop table #tmpDonorSrokG
 drop table #tmpASNAMarketing
 drop table #tmpConstellationProductList
 drop table #tmpConstellationCompleteList

END
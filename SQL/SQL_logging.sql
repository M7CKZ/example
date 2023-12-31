
-- =============================================
-- Author:		Калашников В.Л.
-- Create date: 08.02.2022
-- Description:	Сохранение приоритета производителя
-- 05.12.2022 - (v2) Калашников В.Л. - переход на новые дубли, рефакторинг
-- =============================================

/*
 До сих пор очень нравится решение. 
 Мне было необходимо либо добавить настройку, либо отредактировать старую + залогировать изменения
*/

 -- логирование
 insert into ExternalData.dbo.AutoZakazFabrPriorityLog(customerId, drugId, formId, fabrId, columnName, oldValue, newValue, changeDate, personId)
 select t.parentCustomerId, t.drugId, t.formId, t.fabrId, 'priority', t.oldValue, t.newValue, t.changeDate, t.personId
 from (
  merge Miracle.dbo.AutoZakazFabrPriority as trg
   using (
    select l.drugId, l.formId, l.fabrId
    from @tblProductList as l
   ) as src on trg.drugId = src.drugId and trg.formId = src.formId and trg.fabrId = src.fabrId and trg.parentCustomerId = @parentCustomerId
   when matched then update set 
	trg.priority = @priority, trg.changeDate = GETDATE()
   when not matched then
    insert (parentCustomerId, drugId, formId, fabrId, [priority], changeDate, personId)
    values(@parentCustomerId, src.drugId, src.formId, src.fabrId, @priority, GETDATE(), @personId)
   output
    inserted.parentCustomerId, inserted.drugId, inserted.formId, inserted.fabrId, deleted.[priority] as oldValue,
    inserted.[priority] as newValue, inserted.changeDate, inserted.personId
 ) t
 where isnull(t.oldValue, -1) != isnull(t.newValue, -1)

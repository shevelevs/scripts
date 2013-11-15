
if not exists(select * from sysobjects where name = '%object_name%' and type in (N'P', N'PC'))
  exec('create PROCEDURE dbo.%object_name% as select ''%object_name% is not implemented'' return -1')
GO

%object_ddl%

go

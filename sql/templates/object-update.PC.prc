
if exists(select * from sysobjects where name = '%object_name%' and type in (N'P', N'PC'))
  DROP PROCEDURE dbo.%object_name%
go

%object_ddl%

go

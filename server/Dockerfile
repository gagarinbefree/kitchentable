FROM mcr.microsoft.com/dotnet/sdk:10.0.404 AS sdk
WORKDIR /src
COPY src/KitchenTable.Server.csproj src/
RUN dotnet restore src/KitchenTable.Server.csproj
COPY src/ src/
FROM sdk AS publish
RUN dotnet publish src/KitchenTable.Server.csproj -c Release --no-restore -o /out
FROM sdk AS tests
COPY tests/ tests/
RUN dotnet build tests/KitchenTable.Tests -c Release
ENTRYPOINT ["dotnet", "test", "tests/KitchenTable.Tests", "-c", "Release", "--no-build"]
FROM mcr.microsoft.com/dotnet/aspnet:10.0.15 AS runtime
WORKDIR /app
COPY --from=publish /out .
USER $APP_UID
ENTRYPOINT ["dotnet", "KitchenTable.Server.dll"]

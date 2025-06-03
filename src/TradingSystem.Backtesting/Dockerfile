FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore
COPY ["TradingSystem.Backtesting/TradingSystem.Backtesting.csproj", "TradingSystem.Backtesting/"]
COPY ["TradingSystem.Core/TradingSystem.Core.csproj", "TradingSystem.Core/"]
RUN dotnet restore "TradingSystem.Backtesting/TradingSystem.Backtesting.csproj"

# Copy everything and build
COPY . .
RUN dotnet build "TradingSystem.Backtesting/TradingSystem.Backtesting.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "TradingSystem.Backtesting/TradingSystem.Backtesting.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

ENV ASPNETCORE_URLS=http://+:80
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "TradingSystem.Backtesting.dll"]

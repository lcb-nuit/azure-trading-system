FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore
COPY ["TradingSystem.Web/TradingSystem.Web.csproj", "TradingSystem.Web/"]
COPY ["TradingSystem.Core/TradingSystem.Core.csproj", "TradingSystem.Core/"]
RUN dotnet restore "TradingSystem.Web/TradingSystem.Web.csproj"

# Copy everything and build
COPY . .
RUN dotnet build "TradingSystem.Web/TradingSystem.Web.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "TradingSystem.Web/TradingSystem.Web.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

ENV ASPNETCORE_URLS=http://+:80
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "TradingSystem.Web.dll"]

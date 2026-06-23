// Copyright (c) 2026 SEFE Securing Energy for Europe GmbH.
// SPDX-License-Identifier: Apache-2.0

using System.Text;
using Serilog.Events;
using Serilog.Formatting;
using IdentityServer.Core.Serilog.Entities;

namespace IdentityServer.Core.Serilog;

public class TradingTextFormatter : ITextFormatter
{
    private readonly SerilogEventToTradingEventMapper _mapper;

    public TradingTextFormatter(string applicationName)
    {
        _mapper = new SerilogEventToTradingEventMapper(applicationName);
    }

    public void Format(LogEvent logEvent, TextWriter output)
    {
        TradingLogEvent tcsLogEvent = _mapper.Map(logEvent);
        if (output is StreamWriter)
        {
            string value = tcsLogEvent.Serialize();
            output.Write(value);
            output.WriteLine();
        }
        else
        {
            StringBuilder stringBuilder = new();
            output.WriteLine(tcsLogEvent.Serialize(stringBuilder).ToString());
        }
    }
}

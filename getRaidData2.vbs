Function Login(URL)
    Set WinHttpReq = CreateObject("WinHttp.WinHttpRequest.5.1")
    WinHttpReq.Open "POST", URL, False
'	WinHttpReq.setRequestHeader "Content-type:", "application/x-www-form-urlencoded"
	Const WinHttpRequestOption_EnableRedirects= 6
	WinHttpReq.Option(WinHttpRequestOption_EnableRedirects) = "True"
	WinHttpReq.Send

	str = WinHttpReq.GetAllResponseHeaders
	arrHeader = split(WinHttpReq.GetAllResponseHeaders,vbcrlf)
	dim strCookies
	dim intCookies

	for i = 0 to UBound(arrHeader)
	    if Left(arrHeader(i),10)  = "Set-Cookie" then
		    strCookies = strCookies & Mid(arrHeader(i),12) & "; "
		    intCookies = intCookies + 1
	    end if
	Next

	Login = strCookies
End Function

Function ReadPage(URL, cookies)
    PageText = ""

    Set WinHttpReq = CreateObject("WinHttp.WinHttpRequest.5.1")
    WinHttpReq.Open "GET", URL, False
    If cookies <> null Then
'	WinHttpReq.SetRequestHeader "Depth", "0"
'	WinHttpReq.SetRequestHeader "Content-Type","text/xml"
    	WinHttpReq.SetRequestHeader "Cookie", "Necessary according to Q234486"
	    WinHttpReq.SetRequestHeader "Cookie",cookies
    End If
    WinHttpReq.Send

    If (WinHttpReq.Status = 200) Then
        PageText = WinHttpReq.ResponseText
    End If

    ReadPage = PageText
End Function

Function ScrapeSection(table, message)

    scraped = ""
    iName = -1
    iNote = -1
    iRole = -1
    For iCell = 0 To table.rows(0).cells.Length - 1
        hdrText = InnermostChild(table.rows(0).cells(iCell)).nodeValue
        If left(hdrText, 4) = "Name" then
            iName = iCell
        ElseIf left(hdrText, 8) = "Comments" then
            iNote = iCell
        ElseIf left(hdrText, 4) = "Role" then
            iRole = iCell
        End If
    Next

    For iRow = 1 to table.rows.Length - 1
        attendName = ""
        attendNote = ""
        attendRole = ""
        If iName <> -1 then
            attendName = InnermostChild(table.rows(iRow).cells(iName)).nodeValue
        End If
        If iNote <> -1 then
            attendNote = InnermostChild(table.rows(iRow).cells(iNote)).nodeValue
            If attendNote <> "-" then
                tooltipNote = "" & InnermostChild(table.rows(iRow).cells(iNote)).parentNode.getAttribute("onmouseover")
                s = InStr(tooltipNote,"<br>")
                If s <> 0 then
                    e = InStr(s, tooltipNote,",this")
                    attendNote = Mid(tooltipNote, s, e-s-1)
                    attendNote = Replace(attendNote, "<br>", "")
                    attendNote = Replace(attendNote, vbCRLF, "\n")
                    attendNote = Replace(attendNote, chr(34), "\" & """")
                End If
            Else
                attendNote = ""
            End If
        End If
        If iRole <> -1 then
            attendRole = InnermostChild(table.rows(iRow).cells(iRole)).nodeValue
            e = InStr(attendRole, " ")
            If e <> 0 then
                attendRole = Left(attendRole, e-1)
            End If
        End If

        scraped = scraped & "    """
        scraped = scraped & Trim(attendName)
        scraped = scraped & ":" & message & ":" & Trim(attendRole)
        scraped = scraped & ":" & Trim(attendNote) & ""","
        scraped = scraped & vbCrLf
    Next
    ScrapeSection = scraped
End Function

Function InnermostChild(node)
    While not (node.firstChild is nothing or isNull(node.firstChild))
        Set node = node.firstChild
    Wend
    Set InnermostChild = node
End Function

Function ScrapeRaidList(PageText)
    locList = -1
    locDate = -1
    locUrl = -1
    tblTitle = ""

    Set oDoc = CreateObject("HtmlFile")
    oDoc.Open
    oDoc.write PageText
    oDoc.Close

    scraped = ""

    Set content = oDoc.getElementById("contentContainer")
    Set tables = content.getElementsByTagName("table")

    ' The top row may be the header, or the page selector, dpeending on number
    ' of events in the list. Outer for detects the correct location.
    ' At exit, locRowStart holds the first row that contains raid data
    For iRow = 0 to 1
        Set cells = Tables(0).Rows(iRow).Cells
        locRowStart = iRow + 1
        For iCol = 0 to cells.Length - 1
            Set cell = InnermostChild(cells(iCol))
            If not (cell is nothing or isNull(cell)) Then
                cellTitle = trim(cell.nodeValue)
                If left(cellTitle,4) = "Date" Then locDate = iCol
                If left(cellTitle,7) = "Dungeon" Then locUrl = iCol
                If locDate <> -1 And locUrl <> -1 Then Exit For
            End If
        Next
        If locDate <> -1 And locUrl <> -1 Then Exit For
    Next

    If locDate <> -1 And locUrl <> -1 Then
        For iRow = locRowStart to Tables(0).Rows.Length - 1
            Set cell1 = InnermostChild(Tables(0).Rows(iRow).Cells(locUrl))
            scraped = scraped & _
                "<option value=""" & _
                    Replace(cell1.parentNode.getAttribute("href"), "about:", "") & """>"
            Set cell2 = InnermostChild(Tables(0).Rows(iRow).Cells(locDate))
            scraped = scraped & cell2.nodeValue
            scraped = scraped & " - " & cell1.nodeValue & "</option>"
        Next
    End If

    ScrapeRaidList = scraped
End Function

Function ScrapeRaidData(PageText)
    locConfirTbl = -1
    locSignedTbl = -1
    locNotsurTbl = -1
    locUnsignTbl = -1
    tblTitle = ""

    Set oDoc = CreateObject("HtmlFile")
    oDoc.Open
    oDoc.write PageText
    oDoc.Close

    scraped = ""

    Set content = oDoc.getElementById("contentContainer")
    set divs = content.getElementsByTagName("div")

    For mx = 0 To divs.Length - 1
        if divs(mx).className = "contentHeader" then
            hdrText = divs(mx).InnerText
            Set sectionTbls = divs(mx+1).getElementsByTagName("table")
            if left(hdrText, 5) = "melee" or _
               left(hdrText, 6) = "ranged" or _
               left(hdrText, 4) = "tank" or _
               left(hdrText, 6) = "hybrid" or _
               left(hdrText, 6) = "healer" then
                scraped = scraped & ScrapeSection(sectionTbls(0), "signed")
            Elseif left(hdrText,6) = "Queued" then
                scraped = scraped & ScrapeSection(sectionTbls(0), "unsure")
            Elseif left(hdrText,9) = "Cancelled" then
                scraped = scraped & ScrapeSection(sectionTbls(0), "unsigned")
            End If
        End If
    Next

    ScrapeRaidData = scraped
End Function

Function GetSessionId(url)
    s = InStr(url, "s=") + 2
    e = InStr(s, url, "&")
    if e <> 0 Then
        GetSessionId = Mid(url, s, e - s)
    Else
        GetSessionId = Mid(url, s)
    End if
End Function

Function GetRaidId(url)
    s = InStr(url, "raid_id=") + 8
    e = InStr(s, url, "&")
    if e <> 0 Then
        GetRaidId = Mid(url, s, e - s)
    Else
        GetRaidId = Mid(url, s)
    End if
End Function

FormDone = 0
Sub OkClicked
	FormDone = 1
End Sub

Set fso = CreateObject("Scripting.FileSystemObject")
With fso
    If .FileExists(outFileName) Then
        .DeleteFile outFileName
    End If
End With

raidListPage = ReadPage("http://www.zebraguild.com/wrm/index.php?Sort=Date&SortDescending=1", null)
'raidListPage = ReadPage("http://www.zebraguild.com/wrm/index.php", null)
choices = ScrapeRaidList(raidListPage)

Set ie = WScript.CreateObject("InternetExplorer.Application", "IE_")

'path = WScript.ScriptFullName
'path = Left(path, InstrRev(path, "\"))
'ie.navigate path & "form.html"
ie.navigate "about:blank"
Do While (ie.Busy) ' Important: wait till MSIE is ready
    WScript.Sleep 200  ' suspend 200 ms to lower CPU load
Loop
ie.Document.open
ie.Document.write "<html>"
ie.Document.write "<head><title>Riddle me this, Batman</title></head>"
ie.Document.write "<BODY style=""background:#c0c0c0;"" scroll=""no""><table><tr><td><font size=""2"" face=""Arial"">Username:</font></td><td>" &_
"<font face=""Arial""><input type=""text"" name=""UserName"" size=""40"">" &_
"</font></td></tr><tr><td><font size=""2"" face=""Arial"">Password:</font></td>" &_
"<td><font face=""Arial""><input type=""password"" name=""UserPassword"" size=""40""></font></td>" &_
"</tr><tr><td><font size=""2"" face=""Arial"">Raid Date:</font></td><td><font face=""Arial"">" &_
"<select name=""RaidUrl"">" & choices & "</select>" &_
"</font></td></tr></table>" &_
"<input id=runbutton class=""button"" type=""button"" value="" OK "" name=""ok_button""></BODY>"
ie.Document.close

ie.ToolBar = 0
ie.StatusBar = 0
ie.Width = 400
ie.Height = 170
ie.Left = 300
ie.Top = 200
ie.Visible = 1
ie.Document.Body.All.ok_button.onclick = GetRef("OkClicked")
Do While (FormDone <> 1)
    Wscript.Sleep 250
Loop

userName = ie.Document.Body.All.UserName.Value
password = ie.Document.Body.All.UserPassword.Value
raidUrl = ie.Document.Body.All.RaidUrl.Value
ie.Quit
Wscript.Sleep 250

' FIXME: Maybe add a cancel
If strButton = "Cancelled" Then
    Wscript.Quit
End If

sessionId = GetSessionId(raidUrl)
raidId = GetRaidId(raidUrl)
cookies = ""

raidPage = ReadPage("http://www.zebraguild.com/wrm/" & raidUrl, cookies)
' Parse the planned tables, and prepare output (raidData variable holds it)
raidId = raidId & "_" & FormatDateTime(Now(), vbShortDate)
raidData = "ZebRaid.RaidID = """ & raidId & """" & vbCrLf
raidData = raidData & "ZebRaid.Signups = {" & vbCrLf
raidData = raidData & ScrapeRaidData(raidPage)
raidData = raidData & "};" & vbCrLf

' Report the results
Const outFileName = "signups.lua"

With fso
    If .FileExists(outFileName) Then
        .DeleteFile outFileName
    End If
End With

' Write to file in UTF-8 format. WoW wants it.
With CreateObject("adodb.stream")
        .Type = 2
        .Open
        .Charset = "utf-8"
        .WriteText raidData
        .savetoFile outFileName
End With

MsgBox ("Raid data written to " & outFileName & " successfully")
            'WScript.StdOut.WriteLine("hdrText = " & hdrText)


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

Function ScrapeTable(Cells, message)

    scraped = ""

    For classrow = 0 To Cells.Length - 1
        attendName = ""
        attendNote = ""
        attendRoll = ""
        Set Members = Cells(classrow).Children
        Set member = Members(0).Rows(1).Cells(0)
        For i = 0 To member.Children.Length - 1

            Set cmember = member.Children(i)

        	cell0 = Trim(cmember.Rows(1).Cells(0).innerHTML)
        	bul = InStr(cell0, "up.png") ' Check if we have a class leader here
        	shiftIdx = 0
        	if bul <> 0 Then shiftIdx = 1

            attendName = Trim(cmember.Rows(1).Cells(shiftIdx + 1).innertext)
            attendNote = Trim(cmember.Rows(1).Cells(shiftIdx + 0).innerHTML)
            attendRoll = Trim(cmember.Rows(1).Cells(shiftIdx + 2).innerHTML)

            If attendNote <> "" Then
                bul = InStr(attendNote, "note.png")
				If bul <> 0 Then
	                attendNote = Mid(attendNote, bul + 21)
	                bul = InStr(attendNote, "<td>")
	            End If
				If bul <> 0 Then
	                attendNote = Trim(Mid(attendNote, bul + 5))
	                bul = InStr(attendNote, "</td>")
	            End If
				If bul <> 0 Then
	                attendNote = Trim(Left(attendNote, bul - 1))
	            Else
	            	attendNote = ""
                End If
	        End If

            If attendRoll <> "" Then
                bul = InStr(attendRoll, "roll.png")
                attendRoll = Mid(attendRoll, bul + 21)
                bul = InStr(attendRoll, "<td>")
                attendRoll = Trim(Mid(attendRoll, bul + 5))
                bul = InStr(attendRoll, "</td>")
                attendRoll = Trim(Left(attendRoll, bul - 1))
            End If
            scraped = scraped & "    """
            scraped = scraped & attendName
            scraped = scraped & ":" & message & ":" & attendRoll
            scraped = scraped & ":" & attendNote & ""","
            scraped = scraped & vbCrLf
        Next
'        For i = 0 To Members.Length - 1
'            Set member = Members(i).Rows(1).Cells
'            scraped = scraped & "    """
'            scraped = scraped & Trim(member(1).Children(0).innerText)
'            scraped = scraped & ":" & message & ":" & Trim(member(3).innerText)
'            ' Can't get member(0).children(0) to work.
'            note = member(0).innerHTML
'            If Len(note) > 0 Then
'                note = Replace(note, "<A onmouseover=""overlib('", "")
'                note = Left(note, InStr(note, "',") - 1)
'            End If
'            scraped = scraped & ":" & Trim(note) & ""","
'            scraped = scraped & vbCrLf
'        Next
    Next
    ScrapeTable = scraped
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

    Set Tables = oDoc.getElementsByTagName("table")

    For iTbl = 0 to Tables.Length - 1
        tblTitle = trim(Tables(iTbl).Rows(0).innerText)
        If Left(tblTitle, 13) = "Current Raids" Then
            locList = iTbl
            Exit For
        End If
    Next

    If locList <> -1 then
        Set cells = Tables(locList).Rows(1).Cells
        For iCol = 0 to cells.Length - 1
            Set cell = InnermostChild(cells(iCol))
            If not (cell is nothing or isNull(cell)) Then
                cellTitle = trim(cell.nodeValue)
                If left(cellTitle,4) = "Date" Then locDate = iCol
                If left(cellTitle,4) = "Name" Then locUrl = iCol
                If locDate <> -1 And locUrl <> -1 Then Exit For
            End If
        Next
    End If

    If locList<> -1 And locDate <> -1 And locUrl <> -1 Then
        For iRow = 2 to Tables(locList).Rows.Length - 3
            Set cell = InnermostChild(Tables(locList).Rows(iRow).Cells(locUrl))
            scraped = scraped & _
                "<option value=""" & _
                    Replace(cell.parentNode.getAttribute("href"), "about:", "") & """>"
            Set cell = InnermostChild(Tables(locList).Rows(iRow).Cells(locDate))
            scraped = scraped & cell.nodeValue & "</option>"
        Next
    End If

    ScrapeRaidList = scraped
End Function

Function ScrapeData(PageText)
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

    For mx = 0 To oDoc.getElementsByTagName("table").Length - 1
        tblTitle = Trim(oDoc.getElementsByTagName("table")(mx).Rows(0).innertext)

        If Left(tblTitle, 11) = "Confirmed (" Then locConfirTbl = mx + 1
        If Left(tblTitle, 8) = "Signed (" Then locSignedTbl = mx + 1
        If Left(tblTitle, 10) = "Unsigned (" Then locUnsignTbl = mx + 1
        If Left(tblTitle, 10) = "Not Sure (" Then locNotsurTbl = mx + 1
    Next
    ' Get the confirmed list as signed
    'Set signedCells = oDoc.getElementsByTagName("table")(5).Rows(2).Cells
    Set signedCells = oDoc.getElementsByTagName("table")(locConfirTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "signed")

    ' Get the signed list
    Set signedCells = oDoc.getElementsByTagName("table")(locSignedTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "signed")

    ' Get the unsigned list
    Set signedCells = oDoc.getElementsByTagName("table")(locUnsignTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "unsigned")

    ' Get the unsure list
    Set signedCells = oDoc.getElementsByTagName("table")(locNotsurTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "unsure")

    ScrapeData = scraped
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
    s = InStr(url, "r=") + 2
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

raidListPage = ReadPage("http://www.zebraguild.com/dkp40/plugins/raidplan/listraids.php?s=", null)
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
cookies = Login("http://www.zebraguild.com/dkp40/login.php?s=" & sessionId & "&username=" & userName & "&password=" & password & "&login=Login")

raidPage = ReadPage("http://www.zebraguild.com/dkp40/plugins/raidplan/" & raidUrl, cookies)
' Parse the planned tables, and prepare output (raidData variable holds it)
raidId = raidId & "_" & FormatDateTime(Now(), vbShortDate)
raidData = "ZebRaid.RaidID = """ & raidId & """" & vbCrLf
raidData = raidData & "ZebRaid.Signups = {" & vbCrLf
raidData = raidData & ScrapeData(raidPage)
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

